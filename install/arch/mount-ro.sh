#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Mount Windows and the Fedora side READ-ONLY for inspection from Arch.
# Run as yourself: bash install/arch/mount-ro.sh        (mount)
#                  bash install/arch/mount-ro.sh off    (unmount everything again)
#
#   /dev/sda3 (Windows, ntfs3)          -> /mnt/windows
#   sda5 subvolume root (Fedora /)      -> /mnt/fedora/root
#   sda5 subvolume home (if it exists)  -> /mnt/fedora/home
#   /dev/sda4 (/boot, ext4)             -> /mnt/fedora/boot
#   /dev/sda1 (ESP, vfat)               -> /mnt/fedora/esp
# Everything is ro,nosuid,nodev,noexec; nothing is written anywhere.
set -euo pipefail

uuid=4d74e1d5-7bca-48bf-a6e0-1362fd77882e
opts=ro,nosuid,nodev,noexec
targets=(/mnt/windows /mnt/fedora/root /mnt/fedora/home /mnt/fedora/boot /mnt/fedora/esp)

if [[ ${1:-} == off ]]; then
  for t in "${targets[@]}"; do
    if mountpoint -q "$t"; then sudo umount "$t"; echo "unmounted $t"; fi
  done
  exit 0
fi

mnt() { # mnt <target> <mount args...>
  local t=$1; shift
  if mountpoint -q "$t"; then echo "already mounted: $t"; return; fi
  sudo mkdir -p "$t"
  sudo mount "$@" "$t" && echo "mounted $t (read-only)"
}

mnt /mnt/windows -t ntfs3 -o $opts /dev/sda3
mnt /mnt/fedora/root -o $opts,subvol=root UUID=$uuid

# Fedora's /home: separate subvolume at the top level, or a directory in root.
top=$(mktemp -d)
sudo mount -o ro,subvolid=5 UUID=$uuid "$top"
echo "subvolumes at the top level of sda5:"; ls -1 "$top" | sed 's/^/  /'
has_home=no; [[ -d $top/home ]] && has_home=yes
sudo umount "$top"; rmdir "$top"
if [[ $has_home == yes ]]; then
  mnt /mnt/fedora/home -o $opts,subvol=home UUID=$uuid
else
  echo "no home subvolume: Fedora's /home is /mnt/fedora/root/home"
fi

mnt /mnt/fedora/boot -t ext4 -o $opts /dev/sda4
mnt /mnt/fedora/esp -t vfat -o $opts /dev/sda1

echo
findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS | grep -E "/mnt/(windows|fedora)"
