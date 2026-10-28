#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# The sleep kernel's 14" DTB is built from the Anatase base, without
# dts/patches; these overlays add what the EL1 DTB has: speakers (0003, 0005,
# 0006), fingerprint (0004) and camera (0001, 0002; first tried at EL2 on
# 28 October). Used by build-sleep-kernel.sh and install/el2/sleep-dtb.sh.
#
#   bash tools/kernel/apply-sleep-overlays.sh IN.dtb OUT.dtb [nocamera]
#
# OUT is padded for GRUB and checked for each overlay's nodes.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
in=$1 out=$2
ovl=(speakers fingerprint camera)
[ "${3:-}" = nocamera ] && ovl=(speakers fingerprint)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

fdtget -l "$in" / | grep -qx __symbols__ || { echo "error: $in has no __symbols__" >&2; exit 1; }
cp "$in" "$work/cur.dtb"
for o in "${ovl[@]}"; do
    dtc -q -@ -I dts -O dtb -o "$work/$o.dtbo" "$repo/dts/src/x1e80100-book4-edge-14-$o.dtso"
    fdtoverlay -i "$work/cur.dtb" -o "$work/next.dtb" "$work/$o.dtbo"
    mv "$work/next.dtb" "$work/cur.dtb"
done
dtc -q -I dtb -O dtb -p 8192 -o "$out" "$work/cur.dtb"   # padded for GRUB

# node of a label, then one of its properties
prop() { fdtget -ts "$out" "$(fdtget -ts "$out" /__symbols__ "$1" 2>/dev/null)" "$2" 2>/dev/null || true; }
[ "$(prop left_tweeter sound-name-prefix)" = TweeterLeft ] || { echo "error: $out has no tweeters" >&2; exit 1; }
[ "$(prop usb_2 status)" = okay ] || { echo "error: $out has no fingerprint reader (usb_2)" >&2; exit 1; }
if [[ " ${ovl[*]} " = *" camera "* ]]; then
    [ "$(prop camss status)" = okay ] || { echo "error: $out has no camera (camss)" >&2; exit 1; }
fi
echo "overlays: ${ovl[*]}"
