#!/usr/bin/env bash
# Write the EL2 Secure-Launch test stick (UEFI Shell + sltest.efi + tcblaunch).
# Run as yourself: bash ~/make-el2-usb.sh /dev/sdX
#
# ERASES the whole USB stick: new GPT with one FAT32 EFI partition, then copies
# ~/src/el2-usb/stage onto it. Refuses anything that is not a USB disk, and
# never touches sda (the internal drive).
set -euo pipefail

stage=$HOME/src/el2-usb/stage
dev=${1:-}

[[ -n $dev && -b $dev ]] || { echo "usage: bash ~/make-el2-usb.sh /dev/sdX   (plug the stick in first)"; lsblk -dpo NAME,TRAN,SIZE,MODEL; exit 1; }
[[ $dev != /dev/sda && $dev != /dev/sda* ]] || { echo "error: $dev is the internal drive; refusing." >&2; exit 1; }
[[ $(lsblk -dno TYPE "$dev") == disk ]] || { echo "error: give the whole disk (e.g. /dev/sdb), not a partition." >&2; exit 1; }
[[ $(lsblk -dno TRAN "$dev") == usb ]] || { echo "error: $dev is not a USB disk; refusing." >&2; exit 1; }
[[ -f $stage/EFI/BOOT/BOOTAA64.EFI && -f $stage/sltest.efi ]] || { echo "error: $stage is incomplete." >&2; exit 1; }

echo "About to ERASE this disk:"
lsblk -po NAME,TRAN,SIZE,FSTYPE,LABEL,MODEL,MOUNTPOINTS "$dev"
read -rp "Type the device name ($dev) to continue: " answer
[[ $answer == "$dev" ]] || { echo "aborted"; exit 1; }

# The disk itself may carry the filesystem (no partition table), and the
# desktop automounts it: unmount the disk and every partition.
for p in $(lsblk -lnpo NAME "$dev"); do
  for m in $(findmnt -rn -o TARGET -S "$p"); do sudo umount "$m" && echo "unmounted $m"; done
done

sudo wipefs -a "$dev"
echo 'label: gpt
,,U,' | sudo sfdisk -q "$dev"
sudo partprobe "$dev"; sudo udevadm settle
part=$(lsblk -lnpo NAME "$dev" | sed -n 2p)
sudo mkfs.fat -F 32 -n EL2TEST "$part"

mnt=$(mktemp -d)
sudo mount "$part" "$mnt"
sudo cp -r "$stage"/. "$mnt"/
sync
echo; echo "Contents:"; (cd "$mnt" && find . -type f | sort)
sudo umount "$mnt"; rmdir "$mnt"
echo; echo "Done. The stick is ready; you can unplug it."
