#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Read-only check of a rescue stick built by rescue-usb.sh, for when it stops
# at a bare "grub>" prompt: that means GRUB's built-in config could not
# search for /book4-rescue.id or load /book4/grub.cfg. Mounts the stick's
# ESP (label BOOK4ESP) read-only and lists what GRUB needs.
#
#   bash install/arch/rescue-usb-check.sh      (stick plugged in, run on Arch)
set -uo pipefail
P=$(blkid -L BOOK4ESP 2>/dev/null) || { echo "No partition labelled BOOK4ESP: is the stick plugged in?" >&2; exit 1; }
echo "== ESP $P"
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTTYPENAME "$(lsblk -no PKNAME "$P" | sed 's|^|/dev/|')"
M=$(mktemp -d)
sudo mount -o ro "$P" "$M" || exit 1
trap 'sudo umount "$M"; rmdir "$M"' EXIT
echo "== files"
sudo find "$M" -type f -printf '%10s  %P\n' | sort -k2
echo "== checks"
for f in book4-rescue.id EFI/BOOT/BOOTAA64.EFI book4/grub.cfg book4/vmlinuz book4/initramfs.img book4/book4.dtb; do
    sudo test -e "$M/$f" && echo "  ok       $f" || echo "  MISSING  $f"
done
echo "== built-in config inside BOOTAA64.EFI (memdisk)"
sudo strings "$M/EFI/BOOT/BOOTAA64.EFI" | grep -E 'book4-rescue.id|set prefix|configfile' | head -5
echo "== book4/grub.cfg"
sudo cat "$M/book4/grub.cfg" 2>/dev/null
