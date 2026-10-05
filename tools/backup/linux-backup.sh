#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Back up everything Linux on this machine (not Windows) to an external drive:
# the btrfs subvolumes (Fedora root + home, Arch), Fedora's /boot, our files
# on the ESP and the partition table. Works from Fedora or Arch, while running.
#
#   bash tools/backup/linux-backup.sh /path/to/mounted/external/drive
#
# On a btrfs destination the subvolumes are received as browsable read-only
# subvolumes; on any other filesystem they are saved as `btrfs send` stream
# files (restore with `btrfs receive`). See RESTORE.md written next to them.
set -euo pipefail
DEST=${1:?usage: $0 /mounted/external/drive}
[ -d "$DEST" ] || { echo "$DEST is not a directory" >&2; exit 1; }
DEV_ROOT=/dev/disk/by-uuid/4d74e1d5-7bca-48bf-a6e0-1362fd77882e
DEV_BOOT=/dev/disk/by-uuid/3c3204e5-ed67-4e72-b0dc-75b7e3cdb3a5
DEV_ESP=/dev/disk/by-uuid/EE27-EF4A
SUBVOLS="root home arch"
STAMP=$(date +%Y%m%d-%H%M)
OUT="$DEST/book4-linux-backup-$STAMP"
TOP=$(mktemp -d)
MB=$(mktemp -d); ME=$(mktemp -d)

sudo -v
cleanup() {
    for s in $SUBVOLS; do
        [ -d "$TOP/.backup-$STAMP-$s" ] && sudo btrfs subvolume delete -q "$TOP/.backup-$STAMP-$s" || true
    done
    for d in "$ME" "$MB" "$TOP"; do mountpoint -q "$d" && sudo umount "$d"; rmdir "$d" 2>/dev/null || true; done
}
trap cleanup EXIT

mkdir -p "$OUT"
sudo mount -o subvolid=5 $DEV_ROOT "$TOP"
need=$(sudo btrfs filesystem usage -b "$TOP" 2>/dev/null | awk '/Used:/{print $2; exit}')
free=$(df -B1 --output=avail "$DEST" | tail -1)
echo "btrfs used: $((need/1024/1024/1024)) GiB, free on destination: $((free/1024/1024/1024)) GiB"
[ "$free" -gt $((need + 3*1024*1024*1024)) ] || { echo "Not enough space on $DEST." >&2; exit 1; }
DESTFS=$(stat -f -c %T "$DEST")

echo "== 1. btrfs subvolumes ($SUBVOLS), read-only snapshots"
for s in $SUBVOLS; do
    [ -d "$TOP/$s" ] || { echo "   no subvolume $s, skipped"; continue; }
    sudo btrfs subvolume snapshot -r "$TOP/$s" "$TOP/.backup-$STAMP-$s" >/dev/null
done
sync
for s in $SUBVOLS; do
    snap="$TOP/.backup-$STAMP-$s"
    [ -d "$snap" ] || continue
    if [ "$DESTFS" = btrfs ]; then
        echo "   $s -> $OUT/ (btrfs receive)"
        sudo btrfs send -q "$snap" | sudo btrfs receive -q "$OUT/"
    else
        echo "   $s -> $OUT/$s.btrfs-send.zst"
        sudo btrfs send -q "$snap" | zstd -q -T0 -3 > "$OUT/$s.btrfs-send.zst"
    fi
done

echo "== 2. Fedora /boot"
sudo mount -o ro $DEV_BOOT "$MB"
sudo tar -C "$MB" --numeric-owner --xattrs --acls -cpf - . | zstd -q -T0 > "$OUT/boot.tar.zst"

echo "== 3. our ESP files (EFI/fedora, EFI/BOOT, EFI/book4; not Windows')"
sudo mount -o ro,umask=0077 $DEV_ESP "$ME"
( cd "$ME" && sudo tar -cpf - $(for d in EFI/fedora EFI/BOOT EFI/book4; do [ -e "$d" ] && echo "$d"; done) ) | zstd -q -T0 > "$OUT/esp-linux.tar.zst"

echo "== 4. partition table and identifiers"
DISK=/dev/$(lsblk -no PKNAME $DEV_ROOT)
sudo sfdisk --dump "$DISK" > "$OUT/partition-table.sfdisk"
lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,PARTUUID "$DISK" > "$OUT/lsblk.txt"
sudo btrfs subvolume list "$TOP" > "$OUT/btrfs-subvolumes.txt"

cat > "$OUT/RESTORE.md" <<EOF
# Restore (Linux side of the Galaxy Book4 Edge), backup $STAMP

Do restores from the *other* Linux (Fedora fixes Arch and vice versa). Never
delete files from the ESP: it is shared with Windows.

- **A subvolume** (e.g. Fedora's \`root\`), from Arch, with the btrfs
  top level mounted at /mnt/top (\`mount -o subvolid=5 /dev/sda5 /mnt/top\`):
  move the broken one aside (\`mv /mnt/top/root /mnt/top/root.broken\`), then
  - btrfs backup: \`btrfs send <backup>/.backup-$STAMP-root | btrfs receive /mnt/top/\`
  - stream file: \`zstd -dc root.btrfs-send.zst | btrfs receive /mnt/top/\`
  then make it writable under the original name:
  \`btrfs subvolume snapshot /mnt/top/.backup-$STAMP-root /mnt/top/root\`
  and delete the received read-only copy. Same for \`home\` and \`arch\`.
- **/boot**: mount /dev/sda4, \`zstd -dc boot.tar.zst | tar -C <mnt> -xpf - --numeric-owner --xattrs --acls\`.
- **ESP**: mount /dev/sda1, \`zstd -dc esp-linux.tar.zst | tar -C <mnt> -xpf -\`
  (overwrites only EFI/fedora, EFI/BOOT, EFI/book4).
- **Partition table**: reference only (\`partition-table.sfdisk\`); do not
  write it back unless the disk was replaced, and then only with care.

If the internal disk is replaced, the laptop needs a bootable rescue medium
with our GRUB, DTB and kernel first; see the repository's docs.
EOF

( cd "$OUT" && find . -maxdepth 1 -type f ! -name SHA256SUMS -exec sha256sum {} + > SHA256SUMS )
du -sh "$OUT" 2>/dev/null | tail -1
echo "Done: $OUT"
