#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# EL2 boot without the USB stick, with the DSPs running (docs/el2.md):
# put the UEFI Shell, qebspil, slbounce and tcblaunch.exe in one new folder on
# the internal ESP, \EFI\book4-el2\, the DSP firmware where qebspil looks for
# it, \firmware\qcom\x1e80100\SAMSUNG\galaxy-book4-edge\ (plain files), and
# add a firmware boot entry "Book4 EL2 (slbounce)" for that shell. The boot
# order is not changed: pick the entry with F10 at power-on. From it, the
# normal GRUB entries still boot at EL1; EL2 entries (EL2 DTB, see
# install/el2/el2-dtb.sh) get EL2 and DSPs started by qebspil.
#
# Nothing on the ESP is deleted or overwritten except files in our own
# folders. Run on Arch at EL1 (efibootmgr needs EFI variables), as yourself:
#
#   bash install/el2/esp-install.sh            install / update
#   bash install/el2/esp-install.sh entry-off  remove only the boot entry
#
# Inputs (built or staged on this machine, see docs/el2.md):
#   ~/src/el2-usb/stage/EFI/BOOT/BOOTAA64.EFI  UEFI Shell (pbatard UEFI-Shell 26H1)
#   ~/src/ext/qebspil/out/qebspilaa64.efi        qebspil + the AOSS load_state patch
#   ~/src/slbounce/out/slbounce.efi              slbounce (+ \EFI\book4-el2\ tcblaunch fallback)
#   ~/src/el2-usb/stage/tcb9616.exe              Windows' tcblaunch.exe 10.0.26100.9616 (never commit)
#   /usr/lib/firmware/updates/qcom/x1e80100/SAMSUNG/galaxy-book4-edge/
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
ESPDEV=/dev/sda1
DIR=EFI/book4-el2
FWDIR=firmware/qcom/x1e80100/SAMSUNG/galaxy-book4-edge
LABEL="Book4 EL2 (slbounce)"
shell=$HOME/src/el2-usb/stage/EFI/BOOT/BOOTAA64.EFI
qeb=$HOME/src/ext/qebspil/out/qebspilaa64.efi
slb=$HOME/src/slbounce/out/slbounce.efi
tcb=$HOME/src/el2-usb/stage/tcb9616.exe
fw=/usr/lib/firmware/updates/qcom/x1e80100/SAMSUNG/galaxy-book4-edge

[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
journalctl -k -b -o cat | grep -c 'All CPU(s) started at EL2' >/dev/null &&
    { echo "error: this is an EL2 boot (no EFI variables); run it on the normal boot" >&2; exit 1; }
command -v efibootmgr >/dev/null || { echo "error: efibootmgr missing (pacman -S efibootmgr)" >&2; exit 1; }
sudo -v
# "Boot0003* Book4 EL2 (slbounce)" possibly followed by a tab and the device path
entry() { sudo efibootmgr | awk -v l="$LABEL" '/^Boot[0-9A-F][0-9A-F][0-9A-F][0-9A-F]/ {
    n = substr($0, 5, 4); t = substr($0, 10); sub(/^\* ?/, "", t); sub(/^ /, "", t); sub(/\t.*/, "", t)
    if (t == l) { print n; exit } }'; }

if [ "${1:-}" = entry-off ]; then
    n=$(entry); [ -n "$n" ] && sudo efibootmgr -q -b "$n" -B && echo "removed Boot$n ($LABEL)" || echo "no '$LABEL' entry"
    exit 0
fi

for f in "$shell" "$qeb" "$slb" "$tcb" "$fw"/qcadsp8380.mbn "$fw"/adsp_dtbs.elf "$fw"/qccdsp8380.mbn "$fw"/cdsp_dtbs.elf; do
    [ -s "$f" ] || { echo "error: missing $f" >&2; exit 1; }
done
strings -el "$slb" | grep -c 'book4-el2' >/dev/null ||
    { echo "error: $slb lacks the \\EFI\\book4-el2\\ tcblaunch fallback; rebuild slbounce" >&2; exit 1; }

esp=$(mktemp -d)
cleanup() { sync; sudo umount "$esp" 2>/dev/null || true; rmdir "$esp"; }
trap cleanup EXIT
if findmnt -rn -S $ESPDEV >/dev/null; then
    echo "error: $ESPDEV is mounted ($(findmnt -rn -o TARGET -S $ESPDEV)); unmount it first" >&2; exit 1
fi
sudo mount -o umask=0077,shortname=winnt $ESPDEV "$esp"
need=$(( $(du -cb "$shell" "$qeb" "$slb" "$tcb" "$fw"/qcadsp8380.mbn "$fw"/adsp_dtbs.elf "$fw"/qccdsp8380.mbn "$fw"/cdsp_dtbs.elf | tail -1 | cut -f1) / 1024 + 1024 ))
free=$(sudo df -k --output=avail "$esp" | tail -1 | tr -d ' ')
echo "ESP: ${free} KiB free, need ~${need} KiB"
[ "$free" -gt "$need" ] || { echo "error: not enough space on the ESP" >&2; exit 1; }

echo "== \\$DIR"
sudo mkdir -p "$esp/$DIR" "$esp/$FWDIR"
sudo install -m 600 "$shell" "$esp/$DIR/Shellaa64.efi"
sudo install -m 600 "$here/startup-esp.nsh" "$esp/$DIR/startup.nsh"
sudo install -m 600 "$qeb" "$esp/$DIR/qebspilaa64.efi"
sudo install -m 600 "$slb" "$esp/$DIR/slbounce.efi"
sudo install -m 600 "$tcb" "$esp/$DIR/tcblaunch.exe"
echo "== \\$FWDIR"
for f in qcadsp8380.mbn adsp_dtbs.elf qccdsp8380.mbn cdsp_dtbs.elf; do
    sudo install -m 600 "$fw/$f" "$esp/$FWDIR/$f"
    sudo cmp -s "$fw/$f" "$esp/$FWDIR/$f" || { echo "error: $f did not copy correctly" >&2; exit 1; }
done
sudo ls -la "$esp/$DIR" "$esp/$FWDIR"
sudo test -e "$esp/EFI/fedora/grubaa64.efi" || echo "WARNING: \\EFI\\fedora\\grubaa64.efi not found; startup.nsh starts that GRUB"

echo "== firmware boot entry"
if [ -n "$(entry)" ]; then
    echo "   '$LABEL' already exists (Boot$(entry))"
else
    order=$(sudo efibootmgr | sed -n 's/^BootOrder: //p')
    sudo efibootmgr -q --create --disk /dev/sda --part 1 --label "$LABEL" --loader "\\${DIR//\//\\}\\Shellaa64.efi"
    n=$(entry); [ -n "$n" ] || { echo "error: entry not created" >&2; exit 1; }
    sudo efibootmgr -q -o "$order${order:+,}$n"   # old order first: the default boot is unchanged
    echo "   created Boot$n, appended to the boot order ($order -> $order${order:+,}$n)"
fi
sudo efibootmgr | grep -E "^BootOrder|$LABEL"
echo
echo "Next: at power-on press F10, pick '$LABEL'; in GRUB pick an EL2 entry (e.g. 'test: el2-sleep')."
