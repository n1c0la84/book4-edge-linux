#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Four speakers on an already installed sleep kernel, without rebuilding it:
# applies dts/src/x1e80100-book4-edge-14-speakers.dtso to /dtb-test/book4-sleep.dtb
# (tweeters, woofers named by side, no 0x43 repeater; build-sleep-kernel.sh
# does the same since 28 October), keeps the old one as
# /dtb-test/book4-sleep.dtb.pre-speakers, then refreshes the EL2 entry with
# install/el2/sleep-setup.sh. Takes effect at the next reboot.
#
# Run on Arch as your user:  bash install/el2/sleep-speakers-dtb.sh
# Undo: restore the .pre-speakers copy over book4-sleep.dtb, rerun sleep-setup.sh.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
dtb=dtb-test/book4-sleep.dtb

[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
if findmnt -rn -S /dev/sda4 >/dev/null; then echo "error: /dev/sda4 (/boot) is mounted; unmount it first" >&2; exit 1; fi
for t in dtc fdtoverlay fdtget; do command -v $t >/dev/null || { echo "error: $t missing" >&2; exit 1; }; done
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
sudo -v

b=$(mktemp -d); sudo mount -o ro /dev/sda4 "$b"
[ -e "$b/$dtb" ] || { sudo umount "$b"; rmdir "$b"; echo "error: no /$dtb; run tools/kernel/build-sleep-kernel.sh" >&2; exit 1; }
cp "$b/$dtb" "$work/base.dtb"; sudo umount "$b"; rmdir "$b"

if [ "$(fdtget -ts "$work/base.dtb" /soc@0/soundwire@6b10000/speaker@0,1 sound-name-prefix 2>/dev/null)" = TweeterLeft ]; then
    echo "/$dtb already has the tweeters"
else
    fdtget -l "$work/base.dtb" / | grep -qx __symbols__ || { echo "error: /$dtb has no __symbols__" >&2; exit 1; }
    dtc -q -@ -I dts -O dtb -o "$work/speakers.dtbo" "$repo/dts/src/x1e80100-book4-edge-14-speakers.dtso"
    fdtoverlay -i "$work/base.dtb" -o "$work/merged.dtb" "$work/speakers.dtbo"
    dtc -q -I dtb -O dtb -p 8192 -o "$work/new.dtb" "$work/merged.dtb"   # padded for GRUB
    [ "$(fdtget -ts "$work/new.dtb" /soc@0/soundwire@6b10000/speaker@0,1 sound-name-prefix)" = TweeterLeft ] ||
        { echo "error: overlay did not add the tweeters" >&2; exit 1; }
    b=$(mktemp -d); sudo mount /dev/sda4 "$b"
    [ -e "$b/$dtb.pre-speakers" ] || sudo cp -p "$b/$dtb" "$b/$dtb.pre-speakers"
    sudo install -m 644 "$work/new.dtb" "$b/$dtb"
    sync; ls -l "$b/$dtb" "$b/$dtb.pre-speakers"; sudo umount "$b"; rmdir "$b"
fi

echo "== refreshing the EL2 entry (sleep-setup.sh)"
bash "$here/sleep-setup.sh"
echo
echo "Reboot into EL2 as usual. Check: amixer -c0 scontrols | grep Tweeter"
