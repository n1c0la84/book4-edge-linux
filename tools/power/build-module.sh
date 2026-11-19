#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build one of the small diagnostic modules in tools/power/<name>/ (a
# Makefile with obj-m and its .c) on Arch, against the running kernel's
# headers (linux-book4-headers: /usr/lib/modules/$(uname -r)/build). Replaces
# the Fedora-container builds (part C, docs/fedora-retired.md). The .ko lands
# next to the source (git-ignored).
#
#   bash tools/power/build-module.sh tools/power/timer-check [KERNEL_BUILD_DIR]
set -euo pipefail
src=$(cd "${1:?module directory, e.g. tools/power/timer-check}" && pwd)
kdir=${2:-/usr/lib/modules/$(uname -r)/build}
[ -e "$src/Makefile" ] || { echo "error: no Makefile in $src" >&2; exit 1; }
[ -e "$kdir/Makefile" ] || { echo "error: no kernel build directory $kdir (pacman -S linux-book4-headers)" >&2; exit 1; }
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
cp "$src"/Makefile "$src"/*.c "$w"/
make -s -C "$kdir" M="$w" modules
for ko in "$w"/*.ko; do
    cp "$ko" "$src/"
    echo "built $src/${ko##*/} ($(modinfo -F vermagic "$ko" | cut -d' ' -f1); running $(uname -r))"
done
