#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Back up everything Linux on this machine (not Windows) to an external drive:
# the running btrfs root subvolume (e.g. arch-45; override with BOOK4_SUBVOLS),
# the Limine second ESP (/boot, sda7), the fallback GRUB /boot (sda4), our
# Linux/EL2 files on the firmware ESP (sda1), EFI boot entries and the
# partition table. Runs while the system is up.
#
#   bash tools/backup/linux-backup.sh /path/to/mounted/external/drive
#
# A network share works too, mounted as a real directory your user can write
# to (not a file manager's smb:// view), e.g. SMB:
#   sudo mount -t cifs //SERVER/SHARE ~/mnt/backup -o username=NAME,uid=$(id -u),gid=$(id -g)
# Keep the laptop plugged in and awake while it runs.
#
# On a btrfs destination the subvolumes are received as browsable read-only
# subvolumes; on any other filesystem they are saved as `btrfs send` stream
# files (restore with `btrfs receive`). See RESTORE.md written next to them.
set -euo pipefail
DEST=${1:?usage: $0 /mounted/external/drive}
[ -d "$DEST" ] || { echo "$DEST is not a directory" >&2; exit 1; }

ROOT_UUID=$(findmnt -rn -t btrfs -o UUID / 2>/dev/null || true)
DEV_ROOT=${BOOK4_DEV_ROOT:-/dev/disk/by-uuid/${ROOT_UUID:-4d74e1d5-7bca-48bf-a6e0-1362fd77882e}}
DEV_LIMINE=${BOOK4_DEV_LIMINE:-/dev/disk/by-uuid/7A97-F511}
DEV_BOOT=${BOOK4_DEV_BOOT:-/dev/disk/by-uuid/3c3204e5-ed67-4e72-b0dc-75b7e3cdb3a5}
DEV_ESP=${BOOK4_DEV_ESP:-/dev/disk/by-uuid/EE27-EF4A}

if [ -n "${BOOK4_SUBVOLS:-}" ]; then
    SUBVOLS=$BOOK4_SUBVOLS
else
    running=$(findmnt -rn -t btrfs -o FSROOT / 2>/dev/null || true)
    running=${running#/}
    [ -n "$running" ] || { echo "could not determine running btrfs subvolume (set BOOK4_SUBVOLS)" >&2; exit 1; }
    SUBVOLS=$running
fi

STAMP=$(date +%Y%m%d-%H%M)
OUT="$DEST/book4-linux-backup-$STAMP"
TOP=$(mktemp -d)
ML=$(mktemp -d); MB=$(mktemp -d); ME=$(mktemp -d)

sudo -v
cleanup() {
    for s in $SUBVOLS; do
        [ -d "$TOP/.backup-$STAMP-$s" ] && sudo btrfs subvolume delete -q "$TOP/.backup-$STAMP-$s" || true
    done
    for d in "$ME" "$MB" "$ML" "$TOP"; do
        mountpoint -q "$d" && sudo umount "$d" || true
        rmdir "$d" 2>/dev/null || true
    done
}
trap cleanup EXIT

mkdir -p "$OUT"
sudo mount -o subvolid=5 "$DEV_ROOT" "$TOP"
need=$(sudo btrfs filesystem usage -b "$TOP" 2>/dev/null | awk '/Used:/{print $2; exit}')
free=$(df -B1 --output=avail "$DEST" | tail -1)
echo "btrfs used: $((need/1024/1024/1024)) GiB, free on destination: $((free/1024/1024/1024)) GiB"
[ "$free" -gt $((need + 3*1024*1024*1024)) ] || { echo "Not enough space on $DEST." >&2; exit 1; }
DESTFS=$(stat -f -c %T "$DEST")

echo "== 1. btrfs subvolumes ($SUBVOLS), read-only snapshots"
for s in $SUBVOLS; do
    [ -d "$TOP/$s" ] || { echo "error: subvolume '$s' does not exist at btrfs top level" >&2; exit 1; }
    sudo btrfs subvolume snapshot -r "$TOP/$s" "$TOP/.backup-$STAMP-$s" >/dev/null
done
sync
backed=0
for s in $SUBVOLS; do
    snap="$TOP/.backup-$STAMP-$s"
    if [ "$DESTFS" = btrfs ]; then
        echo "   $s -> $OUT/ (btrfs receive)"
        sudo btrfs send -q "$snap" | sudo btrfs receive -q "$OUT/"
    else
        echo "   $s -> $OUT/$s.btrfs-send.zst"
        sudo btrfs send -q "$snap" | zstd -q -T0 -3 > "$OUT/$s.btrfs-send.zst"
    fi
    backed=$((backed + 1))
done
[ "$backed" -gt 0 ] || { echo "error: no subvolumes backed up" >&2; exit 1; }

echo "== 2. Limine /boot (BOOK4ESP)"
if [ -e "$DEV_LIMINE" ]; then
    src=$(findmnt -rn -t vfat -S "$DEV_LIMINE" -o TARGET | head -1 || true)
    if [ -z "$src" ]; then
        sudo mount -o ro,umask=0077 "$DEV_LIMINE" "$ML"
        src=$ML
    fi
    sudo tar -C "$src" -cpf - . | zstd -q -T0 > "$OUT/boot-limine.tar.zst"
else
    echo "   not present ($DEV_LIMINE), skipped"
fi

echo "== 3. fallback GRUB /boot (ext4)"
if [ -e "$DEV_BOOT" ]; then
    src=$(findmnt -rn -t ext4 -S "$DEV_BOOT" -o TARGET | head -1 || true)
    if [ -z "$src" ]; then
        sudo mount -o ro "$DEV_BOOT" "$MB"
        src=$MB
    fi
    sudo tar -C "$src" --numeric-owner --xattrs --acls -cpf - . | zstd -q -T0 > "$OUT/boot-grub.tar.zst"
else
    echo "   not present ($DEV_BOOT), skipped"
fi

echo "== 4. our firmware ESP files (EL2 chains, bootloaders, firmware/; not Windows')"
src=$(findmnt -rn -t vfat -S "$DEV_ESP" -o TARGET | head -1 || true)
if [ -z "$src" ]; then
    sudo mount -o ro,umask=0077 "$DEV_ESP" "$ME"
    src=$ME
fi
esp_items=()
for d in EFI/book4-el2-limine EFI/book4-el2-arch EFI/book4-el2 EFI/arch EFI/fedora EFI/BOOT EFI/book4 firmware; do
    [ -e "$src/$d" ] && esp_items+=("$d")
done
[ "${#esp_items[@]}" -gt 0 ] || { echo "error: no Linux/EL2 directories found on $DEV_ESP" >&2; exit 1; }
sudo tar -C "$src" -cpf - "${esp_items[@]}" | zstd -q -T0 > "$OUT/esp-linux.tar.zst"

echo "== 5. partition table, identifiers and EFI boot entries"
DISK=/dev/$(lsblk -no PKNAME "$DEV_ROOT" | head -1)
sudo sfdisk --dump "$DISK" > "$OUT/partition-table.sfdisk"
lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,PARTUUID "$DISK" > "$OUT/lsblk.txt"
sudo btrfs subvolume list "$TOP" > "$OUT/btrfs-subvolumes.txt"
efibootmgr -v > "$OUT/efibootmgr.txt" 2>/dev/null || true

first_sub=${SUBVOLS%% *}
cat > "$OUT/RESTORE.md" <<EOF
# Restore (Linux side of the Galaxy Book4 Edge), backup $STAMP

Do restores from a live medium or another Linux installation. Never delete
files from the firmware ESP (sda1): it is shared with Windows.

- **Root subvolume(s) ($SUBVOLS)**, with the btrfs top level mounted at
  /mnt/top (\`mount -o subvolid=5 /dev/sda5 /mnt/top\`):
  move the broken one aside (\`mv /mnt/top/$first_sub /mnt/top/$first_sub.broken\`), then
  - btrfs backup: \`btrfs send <backup>/.backup-$STAMP-$first_sub | btrfs receive /mnt/top/\`
  - stream file: \`zstd -dc $first_sub.btrfs-send.zst | btrfs receive /mnt/top/\`
  then make it writable under the original name:
  \`btrfs subvolume snapshot /mnt/top/.backup-$STAMP-$first_sub /mnt/top/$first_sub\`
  and delete the received read-only copy.
- **Limine /boot (sda7, BOOK4ESP)**: mount sda7,
  \`zstd -dc boot-limine.tar.zst | tar -C <mnt> -xpf -\`.
- **Fallback GRUB /boot (sda4, ext4)**: if present, mount sda4,
  \`zstd -dc boot-grub.tar.zst | tar -C <mnt> -xpf - --numeric-owner --xattrs --acls\`.
- **Firmware ESP (sda1)**: mount sda1, \`zstd -dc esp-linux.tar.zst | tar -C <mnt> -xpf -\`
  (overwrites only our EL2 chains, bootloaders and \`firmware/\`; leaves
  \`EFI/Microsoft\` untouched).
- **EFI boot entries**: \`efibootmgr.txt\` records the NVRAM entries and BootOrder
  (re-create with \`book4-el2 install-limine\` / \`book4-el2 install\` or \`efibootmgr\`).
- **Partition table**: reference only (\`partition-table.sfdisk\`, \`lsblk.txt\`);
  do not write it back unless the disk was replaced, and then only with care.
EOF

( cd "$OUT" && find . -maxdepth 1 -type f ! -name SHA256SUMS -exec sha256sum {} + > SHA256SUMS )
du -sh "$OUT" 2>/dev/null | tail -1
echo "Done: $OUT"
