#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Delete Fedora and the pre-4.5 Arch copy (ROADMAP "Fedora deletion";
# docs/plan-limine.md steps 0 and 1). Run on Arch (arch-45) as your user, in
# a terminal (sudo asks):
#
#   bash install/arch/fedora-delete.sh          dry run: shows everything, changes nothing
#   bash install/arch/fedora-delete.sh --yes    do it
#
# 0. Backup to ~/backup/boot-YYYYMMDD/: whole sda4 image (dd, 2 GB),
#    efibootmgr -v, ESP listing, both grub.cfg copies.
# 1. GRUB test entries that boot the arch subvolume (book4-extra.cfg).
# 2. Fedora's files on /boot (sda4): rescue images, the fc45 kernel set,
#    its BLS entries (/loader) and /grub2, Fedora's own 7.2.7-book4
#    initramfs, the 7.2.7-book4 Arch initramfs images (their only entries
#    boot the arch subvolume) and DTBs no remaining entry uses.
#    Kept: /vmlinuz-7.2.7-book4, because Fedora's GRUB (\EFI\fedora\grub.cfg,
#    the fallback) finds /boot by that file; everything book4-boot's menu
#    uses; /dtb-test/book4-sleep*.dtb.
# 3. btrfs subvolumes root (Fedora), home (Fedora's home; archived in
#    ~/fedora-archive by fedora-retire.sh, reflinked, so those files keep
#    their data) and arch (Arch before the Omarchy 4.5 copy).
# 4. book4-boot menu, then the result.
# Never writes to the ESP. Undo for 1 and 2: the sda4 image; 3 has no undo.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
DEV_ROOT=/dev/disk/by-uuid/4d74e1d5-7bca-48bf-a6e0-1362fd77882e   # btrfs (sda5 + sda6)
BOOTDEV=/dev/sda4
SUBVOLS=(root home arch)
ANCHOR=/vmlinuz-7.2.7-book4
yes=; [ "${1:-}" = --yes ] && yes=1

die() { echo "error: $*" >&2; exit 1; }
[ -e /etc/arch-release ] || die "run this on Arch"
[ "$(id -u)" != 0 ] || die "run as your user (sudo is used inside)"
running=$(findmnt -rn -o FSROOT /); running=${running#/}
[ "$running" = arch-45 ] || die "the running root is '$running', expected arch-45"
[ "$(findmnt -rn -o UUID /)" = 4d74e1d5-7bca-48bf-a6e0-1362fd77882e ] || die "/ is not on the sda5 btrfs"
for s in "${SUBVOLS[@]}"; do [ "$s" != "$running" ] || die "refusing to delete the running subvolume"; done
! findmnt -rn -S $BOOTDEV >/dev/null || die "$BOOTDEV is mounted; unmount it first"
sudo -v

b=$(mktemp -d); top=$(mktemp -d)
cleanup() { sudo umount "$b" 2>/dev/null || true; sudo umount "$top" 2>/dev/null || true; rmdir "$b" "$top"; }
trap cleanup EXIT
sudo mount -o ro $BOOTDEV "$b"
sudo mount -o ro,subvolid=5 "$DEV_ROOT" "$top"

echo "== 3. subvolumes (top level of the root btrfs)"
sudo btrfs subvolume list -t "$top" | sed 's/^/   /'
for s in "${SUBVOLS[@]}"; do
    sudo btrfs subvolume show "$top/$s" >/dev/null 2>&1 || die "no subvolume $s"
    nested=$(sudo btrfs subvolume list -o "$top/$s" | awk '{print $NF}')
    [ -z "$nested" ] || die "$s has nested subvolumes: $nested"
    printf '   delete %-5s %s\n' "$s" "$(sudo du -sh --apparent-size "$top/$s" 2>/dev/null | cut -f1) (apparent)"
done
[ -e ~/fedora-archive/MANIFEST.txt ] || die "~/fedora-archive/MANIFEST.txt missing: run fedora-retire.sh archive first"

echo "== 1. GRUB test entries on subvol=arch"
mapfile -t drop < <(sudo awk '/^# test-entry: / { n = $3 } /rootflags=subvol=arch( |$)/ && n { print n; n = "" }' "$b/book4-extra.cfg" 2>/dev/null | sort -u)
printf '   %s\n' "${drop[@]:-(none)}"

echo "== 2. files on /boot"
# What the remaining menus use: book4-boot's menu and the test entries kept.
keep_refs=$( { sudo cat "$b/grub/grub.cfg"
               sudo awk -v d=" ${drop[*]} " '/^# test-entry: / { on = index(d, " " $3 " ") == 0 } on' "$b/book4-extra.cfg" 2>/dev/null; } |
             grep -oE '\(\$bootdev\)/[^ ]+' | sed 's/^(\$bootdev)//' | sort -u)
del=()
add() { for p in "$@"; do [ -e "$b$p" ] || [ -L "$b$p" ] || continue
        grep -qxF "$p" <<<"$keep_refs" && { echo "   (kept, in use: $p)"; continue; }
        [ "$p" = "$ANCHOR" ] && continue
        del+=("$p"); done; }
add $(cd "$b" && ls -d -- *-0-rescue-* 2>/dev/null | sed 's|^|/|')
add $(cd "$b" && ls -d -- *fc45* 2>/dev/null | sed 's|^|/|')
add /loader /grub2 /initramfs-7.2.7-book4.img /initramfs-7.2.7-book4.img.prev \
    /initramfs-7.2.7-book4-arch.img /initramfs-7.2.7-book4-arch.img.prev /initramfs-7.2.7-book4-arch-ufstest.img \
    /dtb-alt
for f in $(cd "$b" && sudo find dtb-test -type f -name '*.dtb' -printf '/%p\n' 2>/dev/null); do
    case "$f" in /dtb-test/book4-sleep*.dtb) continue ;; esac
    add "$f"
done
for p in "${del[@]}"; do printf '   delete %-62s %s\n' "$p" "$(sudo du -sh "$b$p" | cut -f1)"; done
echo "   kept for Fedora's GRUB fallback: $ANCHOR"
echo "   /boot now: $(df -h --output=used,size "$b" | tail -1)"

if [ -z "$yes" ]; then echo; echo "Dry run: nothing changed. Run again with --yes."; exit 0; fi

echo "== 0. backup"
bk=~/backup/boot-$(date +%Y%m%d); mkdir -p "$bk"
sudo umount "$b"
sudo dd if=$BOOTDEV of="$bk/sda4.img" bs=4M status=progress conv=fsync
sudo chown "$(id -u):$(id -g)" "$bk/sda4.img"
sudo efibootmgr -v > "$bk/efibootmgr.txt"
esp=$(findmnt -rno TARGET -S /dev/sda1 | head -1) || true
[ -n "$esp" ] || { ls /efi/ >/dev/null 2>&1 || true; esp=$(findmnt -rno TARGET -S /dev/sda1 | head -1) || true; }
if [ -n "$esp" ]; then
    sudo find "$esp" -printf '%TY-%Tm-%Td %s %p\n' > "$bk/esp-listing.txt"
    sudo cat "$esp/EFI/fedora/grub.cfg" > "$bk/esp-EFI-fedora-grub.cfg" || true
fi
echo "   $bk: $(ls "$bk" | tr '\n' ' ')"

echo "== 1. removing test entries"
for n in "${drop[@]}"; do bash "$here/test-entry.sh" remove "$n"; done

echo "== 2. removing files from /boot"
sudo mount $BOOTDEV "$b"
for p in "${del[@]}"; do sudo rm -rf --one-file-system -- "$b$p" && echo "   removed $p"; done
[ -e "$b$ANCHOR" ] || die "$ANCHOR is gone; Fedora's GRUB would not find /boot"
sync; sudo umount "$b"

echo "== 3. deleting subvolumes"
sudo mount -o remount,rw "$top"
for s in "${SUBVOLS[@]}"; do sudo btrfs subvolume delete "$top/$s"; done
sudo btrfs subvolume list -t "$top" | sed 's/^/   /'

echo "== 4. menu and result"
sudo book4-boot menu
bash "$here/test-entry.sh" list
sudo mount -o ro $BOOTDEV "$b"
echo "   /boot: $(df -h --output=used,size,avail "$b" | tail -1)"
echo "   btrfs: space comes back as the cleaner works (btrfs subvolume sync): $(df -h --output=used,avail / | tail -1)"
echo "Done. Next: a reboot through Arch GRUB, and once through the Fedora GRUB fallback."
