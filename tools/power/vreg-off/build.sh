#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build vreg_off.ko for the installed Anatase kernel, from Arch, in the
# Fedora container (install/arch/fedora-shell.sh): an external module build
# against ~/src/patchwork, which writes only to a scratch directory in
# Fedora's home. The module lands next to this script (git-ignored).
#
#   bash tools/power/vreg-off/build.sh [KERNEL_TREE]   (default: ~/src/patchwork, Fedora home)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
tree=${1:-'~/src/patchwork'}
if findmnt -rn -O ro /mnt/fedora/home >/dev/null; then
    echo "error: /mnt/fedora/home is mounted read-only; unmount it first (the container needs it read-write)" >&2
    exit 1
fi
c=$(base64 -w0 "$here/vreg_off.c"); mk=$(base64 -w0 "$here/Makefile")
inner="set -euo pipefail
d=\$(mktemp -d ~/.vreg-off-build.XXXXXX); trap 'rm -rf \$d' EXIT
echo $c | base64 -d > \$d/vreg_off.c; echo $mk | base64 -d > \$d/Makefile
make -s -C $tree LOCALVERSION= M=\$d modules >&2
modinfo -F vermagic \$d/vreg_off.ko >&2
base64 -w0 \$d/vreg_off.ko"
bash "$repo/install/arch/fedora-shell.sh" bash -lc "$inner" > "$here/vreg_off.ko.b64"
base64 -d "$here/vreg_off.ko.b64" > "$here/vreg_off.ko"
rm "$here/vreg_off.ko.b64"
echo "built $here/vreg_off.ko ($(modinfo -F vermagic "$here/vreg_off.ko"); installed kernel: $(uname -r))"
