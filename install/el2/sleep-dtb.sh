#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# The sleep kernel's DTB with what the EL1 DTB has (speakers, fingerprint,
# camera: tools/kernel/apply-sleep-overlays.sh), without rebuilding the
# kernel. Always starts from the DTB as the kernel built it, kept on /boot as
# /dtb-test/book4-sleep.dtb.pre-overlays (build-sleep-kernel.sh writes it;
# the first run here saves it, or takes over the older .pre-speakers copy),
# then refreshes the EL2 entry with install/el2/sleep-setup.sh. Takes effect
# at the next reboot.
#
# Run on Arch as your user:  bash install/el2/sleep-dtb.sh [nocamera|restore]
#   nocamera: speakers and fingerprint only
#   restore:  back to the DTB as built, no overlays
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
dtb=dtb-test/book4-sleep.dtb
mode=${1:-}
case $mode in ""|nocamera|restore) ;; *) echo "usage: $0 [nocamera|restore]" >&2; exit 2 ;; esac

[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
if findmnt -rn -S /dev/sda4 >/dev/null; then echo "error: /dev/sda4 (/boot) is mounted; unmount it first" >&2; exit 1; fi
for t in dtc fdtoverlay fdtget; do command -v $t >/dev/null || { echo "error: $t missing" >&2; exit 1; }; done
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
sudo -v

b=$(mktemp -d); sudo mount /dev/sda4 "$b"
umnt() { sync; sudo umount "$b"; rmdir "$b"; }
[ -e "$b/$dtb" ] || { umnt; echo "error: no /$dtb; run tools/kernel/build-sleep-kernel.sh" >&2; exit 1; }
if [ ! -e "$b/$dtb.pre-overlays" ]; then
    if [ -e "$b/$dtb.pre-speakers" ]; then sudo mv "$b/$dtb.pre-speakers" "$b/$dtb.pre-overlays"
    else sudo cp -p "$b/$dtb" "$b/$dtb.pre-overlays"; fi
fi
cp "$b/$dtb.pre-overlays" "$work/base.dtb"
if [ "$mode" = restore ]; then
    sudo install -m 644 "$work/base.dtb" "$b/$dtb"
else
    bash "$repo/tools/kernel/apply-sleep-overlays.sh" "$work/base.dtb" "$work/new.dtb" $mode
    sudo install -m 644 "$work/new.dtb" "$b/$dtb"
fi
ls -l "$b/$dtb" "$b/$dtb.pre-overlays"; umnt

echo "== refreshing the EL2 entry (sleep-setup.sh)"
bash "$here/sleep-setup.sh"
echo
echo "Reboot into EL2 as usual."
