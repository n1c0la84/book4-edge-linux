#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Make the EL2 variant of a Book4 DTB with dts/src/x1-el2-book4.dtso (upstream
# x1-el2.dtso without the ADSP/CDSP iommus), install it next to the source
# in /boot as NAME-el2.dtb and add the GRUB test entry "el2" (the Arch entry
# with that DTB and id_aa64mmfr0.ecv=1). The source DTB must carry
# __symbols__ (built with -@; the kernel's and ours do). Run on Arch:
#
#   bash install/el2/el2-dtb.sh [/dtb-test/book4-default-1010.dtb]   (path under /boot)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
src=${1:-/dtb-test/book4-default-1010.dtb}
dst=${src%.dtb}-el2.dtb
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
if findmnt -rn -S /dev/sda4 >/dev/null; then echo "error: /dev/sda4 (/boot) is mounted; unmount it first" >&2; exit 1; fi

sudo -v
b=$(mktemp -d); sudo mount -o ro /dev/sda4 "$b"
cp "$b$src" "$work/base.dtb"; sudo umount "$b"
fdtget -l "$work/base.dtb" / | grep -qx __symbols__ || { echo "error: $src has no __symbols__" >&2; exit 1; }

dtc -q -@ -I dts -O dtb -o "$work/el2.dtbo" "$repo/dts/src/x1-el2-book4.dtso"
fdtoverlay -i "$work/base.dtb" -o "$work/merged.dtb" "$work/el2.dtbo"
dtc -q -I dtb -O dtb -p 8192 -o "$work/el2.dtb" "$work/merged.dtb"   # GRUB needs the slack
[ "$(fdtget -ts "$work/el2.dtb" /soc@0/gpu@3d00000/zap-shader status)" = disabled ] ||
    { echo "error: zap shader not disabled: slbounce would not switch" >&2; exit 1; }
echo "== changes against $src:"
diff <(dtc -q -I dtb -O dts "$work/base.dtb") <(dtc -q -I dtb -O dts "$work/el2.dtb") | grep '^[<>]' || true

sudo mount /dev/sda4 "$b"
if [ -e "$b$dst" ] && ! cmp -s "$work/el2.dtb" "$b$dst"; then
    sudo umount "$b"; rmdir "$b"; echo "error: a different $dst exists; not overwriting" >&2; exit 1
fi
sudo install -m 644 "$work/el2.dtb" "$b$dst"; sync
sudo umount "$b"; rmdir "$b"
echo "== installed /boot$dst"
bash "$repo/install/arch/test-entry.sh" add el2 +id_aa64mmfr0.ecv=1 "dtb=$dst"
