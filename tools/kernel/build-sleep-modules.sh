#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Rebuild only the out-of-tree modules of the sleep test kernel 7.2.7-book4s
# (tools/power/sleep-modules + icc_hold) against ~/src/patchwork-sleep in the
# Fedora container, and install them in /usr/lib/modules/7.2.7-book4s/extra.
# The kernel itself must already be built (tools/kernel/build-sleep-kernel.sh).
#
#   bash tools/kernel/build-sleep-modules.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
rel=7.2.7-book4s
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
[ -d /usr/lib/modules/$rel/kernel ] || { echo "error: $rel is not installed; run build-sleep-kernel.sh first" >&2; exit 1; }
if findmnt -rn -O ro /mnt/fedora/home >/dev/null; then
    echo "error: /mnt/fedora/home is mounted read-only; unmount it first" >&2; exit 1
fi
mods=$(tar -cz --exclude='*.ko' --exclude='*.o' -C "$repo/tools/power" sleep-modules icc-hold/icc_hold.c | base64 -w0)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
inner="set -euo pipefail
cd ~/src/patchwork-sleep
[ \"\$(make -s LOCALVERSION=s kernelrelease)\" = $rel ]
m=\$(mktemp -d); echo $mods | base64 -d | tar -xz -C \$m
cp \$m/icc-hold/icc_hold.c \$m/sleep-modules/; echo 'obj-m += icc_hold.o' >> \$m/sleep-modules/Makefile
make -s LOCALVERSION=s M=\$m/sleep-modules modules >&2
tar -cz -C \$m/sleep-modules \$(cd \$m/sleep-modules && ls *.ko) | base64 -w0"
bash "$repo/install/arch/fedora-shell.sh" bash -lc "$inner" > "$work/ko.b64"
mkdir "$work/ko"; base64 -d "$work/ko.b64" | tar -xz -C "$work/ko"
sudo install -D -m 644 -t /usr/lib/modules/$rel/extra "$work"/ko/*.ko
sudo depmod $rel
for k in "$work"/ko/*.ko; do printf '   %s %s\n' "$(basename "$k")" "$(modinfo -F vermagic "$k" | cut -d' ' -f1)"; done
