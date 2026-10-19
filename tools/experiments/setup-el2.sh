#!/usr/bin/env bash
# Prepare the EL2 test boot. Writes ONLY to:
#   - the USB test stick (label EL2TEST): adds slbounce.efi, tcblaunch.exe
#     (= tcblaunch 26100.9616 from this machine's Windows, tested OK) and a
#     startup.nsh that loads slbounce and starts Fedora's GRUB; the sltest
#     files stay (the old startup.nsh is kept as startup-sltest.nsh);
#   - /boot (sda4): dtb-test/book4-el2.dtb and the GRUB test entry "el2".
# Nothing on the ESP, no firmware boot entry. Remove with:
#   install/arch/test-entry.sh remove el2  (and delete /boot/dtb-test/book4-el2.dtb)
# Run as yourself on Arch, with the stick plugged in: bash ~/setup-el2.sh
set -euo pipefail
W=$HOME/src/el2-usb
dtb=$W/dtb/book4-el2.dtb
repo=$HOME/Projects/book4-edge-linux

[ "$(fdtget -ts "$dtb" /soc@0/gpu@3d00000/zap-shader status)" = disabled ] || { echo "error: $dtb is not an EL2 DTB" >&2; exit 1; }
part=$(lsblk -lpno NAME,LABEL | awk '$2=="EL2TEST"{print $1}' | head -1)
[ -n "$part" ] || { echo "error: plug in the EL2TEST stick" >&2; exit 1; }
[ "$(lsblk -dno TRAN "/dev/$(lsblk -no PKNAME "$part")")" = usb ] || { echo "error: $part is not on a USB disk" >&2; exit 1; }

# 1. The stick (udisks mount as your user, no sudo).
mnt=$(findmnt -rno TARGET -S "$part" || true)        # not mounted yet: empty
[ -n "$mnt" ] || mnt=$(udisksctl mount -b "$part" | sed -n 's/^Mounted .* at //p')
[ -n "$mnt" ] && [ -d "$mnt" ] || { echo "error: could not mount $part" >&2; exit 1; }
echo "== stick $part at $mnt"
[ -e "$mnt/startup-sltest.nsh" ] || cp "$mnt/startup.nsh" "$mnt/startup-sltest.nsh"
cp "$HOME/src/slbounce/out/slbounce.efi" "$mnt/slbounce.efi"
cp "$W/stage/tcb9616.exe" "$mnt/tcblaunch.exe"
cp "$W/startup-el2.nsh" "$mnt/startup.nsh"
sync
for f in slbounce.efi tcblaunch.exe startup.nsh; do
  src=$( case $f in slbounce.efi) echo "$HOME/src/slbounce/out/slbounce.efi";; tcblaunch.exe) echo "$W/stage/tcb9616.exe";; *) echo "$W/startup-el2.nsh";; esac )
  cmp -s "$src" "$mnt/$f" && echo "   OK $f" || { echo "   BAD $f" >&2; exit 1; }
done
ls "$mnt"
udisksctl unmount -b "$part" >/dev/null && echo "== stick unmounted"

# 2. /boot: the EL2 DTB, then the GRUB test entry.
if findmnt -rn -S /dev/sda4 >/dev/null || findmnt -rn -S /dev/sda1 >/dev/null; then bash ~/mount-ro.sh off; fi
sudo -v
b=$(mktemp -d); sudo mount /dev/sda4 "$b"
if [ -e "$b/dtb-test/book4-el2.dtb" ] && ! cmp -s "$dtb" "$b/dtb-test/book4-el2.dtb"; then
  echo "error: a different /boot/dtb-test/book4-el2.dtb exists; not overwriting" >&2; sudo umount "$b"; rmdir "$b"; exit 1
fi
sudo install -m 644 "$dtb" "$b/dtb-test/book4-el2.dtb"; sync
echo "== installed /boot/dtb-test/book4-el2.dtb"
sudo umount "$b"; rmdir "$b"
bash "$repo/install/arch/test-entry.sh" add el2 +id_aa64mmfr0.ecv=1 dtb=/dtb-test/book4-el2.dtb
