#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build ufs-qcom.ko with one patch (default ufs-qcom-max-bw-during-phy-init.patch),
# from Arch, in the Fedora container, without touching the kernel tree:
# ~/src/patchwork is reflink-copied (instant, shared extents on btrfs) to
# ~/src/patchwork-<patch name> in Fedora's home, patched and built there
# (incremental). Delete that copy when done. Then:
# tools/power/make-ufstest-initramfs.sh.
#
#   bash tools/power/build-ufs-patch.sh [PATCH]
#
# Output: ${BOOK4_POWER_OUT:-~/src/book4-acpi}/modules/ufs-qcom.ko
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
out=${BOOK4_POWER_OUT:-$HOME/src/book4-acpi}/modules
mkdir -p "$out"
if findmnt -rn -O ro /mnt/fedora/home >/dev/null; then
    echo "error: /mnt/fedora/home is mounted read-only; unmount it first" >&2; exit 1
fi
patchfile=${1:-$here/ufs-qcom-max-bw-during-phy-init.patch}
[ -r "$patchfile" ] || { echo "error: $patchfile not found" >&2; exit 1; }
copy=patchwork-$(basename "$patchfile" .patch)
pb=$(base64 -w0 <(sed -n '/^--- a\//,$p' "$patchfile"))
inner="set -euo pipefail
cd ~/src
if [ ! -e $copy ]; then
    echo '== reflink copy ~/src/patchwork -> ~/src/$copy' >&2
    cp -a --reflink=always patchwork $copy
fi
cd $copy
[ \"\$(make -s LOCALVERSION= kernelrelease)\" = \"\$(make -s -C ~/src/patchwork LOCALVERSION= kernelrelease)\" ]
echo $pb | base64 -d > /tmp/ufs.patch
if patch -p1 -R --dry-run -s -f < /tmp/ufs.patch >/dev/null 2>&1; then echo 'patch already applied' >&2
else patch -p1 --forward < /tmp/ufs.patch >&2; fi
make -s -j\$(nproc) LOCALVERSION= modules >&2
modinfo -F vermagic drivers/ufs/host/ufs-qcom.ko >&2
base64 -w0 drivers/ufs/host/ufs-qcom.ko"
bash "$repo/install/arch/fedora-shell.sh" bash -lc "$inner" > "$out/ufs-qcom.ko.b64"
base64 -d "$out/ufs-qcom.ko.b64" > "$out/ufs-qcom.ko"
rm "$out/ufs-qcom.ko.b64"
echo "built $out/ufs-qcom.ko ($(modinfo -F vermagic "$out/ufs-qcom.ko"))"
