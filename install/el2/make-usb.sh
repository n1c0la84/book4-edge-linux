#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Write the EL2 USB stick: UEFI Shell + slbounce + sltest + tcblaunch.exe.
# Booted with F10, its startup.nsh loads slbounce and starts Fedora's GRUB
# from the internal ESP; only a GRUB entry with an EL2 DTB (GPU zap shader
# disabled) then switches to EL2. Nothing is written to the ESP or to UEFI
# variables. To test Secure-Launch alone: Esc at the shell's startup, then
# "sltest.efi \tcblaunch.exe" (green band at the top + hang = EL2 reached).
# Run on Arch as your user; ERASES the stick:
#
#   bash install/el2/make-usb.sh /dev/sdX [TCBLAUNCH.EXE]
#
# Needs slbounce built natively: git clone --recursive
#   https://github.com/TravMurav/slbounce ~/src/slbounce && make -C ~/src/slbounce CROSS_COMPILE=
# TCBLAUNCH.EXE defaults to Windows' own (Windows partition mounted read-only
# at /mnt/windows); it is Microsoft's, never commit it. 10.0.26100.9616
# and 10.0.26100.4351 both reached EL2 on this machine (15 October 2026).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
dev=${1:-}
tcb=${2:-/mnt/windows/Windows/System32/tcblaunch.exe}
sl=${SLBOUNCE_OUT:-$HOME/src/slbounce/out}
# UEFI Shell from github.com/pbatard/UEFI-Shell, release 26H1 (pinned).
shell_url=https://github.com/pbatard/UEFI-Shell/releases/download/26H1/shellaa64.efi
shell_sha=1569b6db4e391c3c59194aa3319a3945efb800fb25349eb9d36ff3d258517ea6

[[ -n $dev && -b $dev ]] || { echo "usage: bash install/el2/make-usb.sh /dev/sdX [tcblaunch.exe]"; lsblk -dpo NAME,TRAN,SIZE,MODEL; exit 1; }
[[ $dev != /dev/sda* ]] || { echo "error: $dev is the internal drive; refusing." >&2; exit 1; }
[[ $(lsblk -dno TYPE "$dev") == disk ]] || { echo "error: give the whole disk (e.g. /dev/sdb)." >&2; exit 1; }
[[ $(lsblk -dno TRAN "$dev") == usb ]] || { echo "error: $dev is not a USB disk; refusing." >&2; exit 1; }
for f in "$sl/slbounce.efi" "$sl/sltest.efi" "$tcb"; do [ -r "$f" ] || { echo "error: $f missing" >&2; exit 1; }; done

stage=$(mktemp -d); trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/EFI/BOOT"
curl -sSfL -o "$stage/EFI/BOOT/BOOTAA64.EFI" "$shell_url"
echo "$shell_sha  $stage/EFI/BOOT/BOOTAA64.EFI" | sha256sum -c --quiet
cp "$sl/slbounce.efi" "$sl/sltest.efi" "$stage/"
cp "$tcb" "$stage/tcblaunch.exe"
cp "$here/startup-el2.nsh" "$stage/startup.nsh"
echo "tcblaunch.exe: $(python3 -I - "$stage/tcblaunch.exe" <<'EOF'
import sys
d = open(sys.argv[1], 'rb').read(); i = d.find('FileVersion'.encode('utf-16-le'))
print(d[i+26:i+90].decode('utf-16-le', 'replace').split('\x00')[0] if i >= 0 else 'unknown version')
EOF
)"

echo "About to ERASE this disk:"
lsblk -po NAME,TRAN,SIZE,FSTYPE,LABEL,MODEL,MOUNTPOINTS "$dev"
read -rp "Type the device name ($dev) to continue: " answer
[[ $answer == "$dev" ]] || { echo "aborted"; exit 1; }
# The disk itself may carry the filesystem and the desktop automounts it.
for p in $(lsblk -lnpo NAME "$dev"); do
    for m in $(findmnt -rn -o TARGET -S "$p"); do sudo umount "$m"; done
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
# Cheap sticks drop off the bus mid-write: verify every file.
(cd "$stage" && find . -type f) | while read -r f; do
    sudo cmp -s "$stage/$f" "$mnt/$f" || { echo "error: $f differs on the stick; write it again" >&2; exit 1; }
done
sudo umount "$mnt"; rmdir "$mnt"
echo "Done, verified. Boot it with F10 (EFI shell -> slbounce -> GRUB)."
