#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Rebuild only samsung-galaxybook-ec.ko (battery, AC adapter, keyboard
# backlight) for an installed Anatase kernel, with the patches from
# drivers/anatase/patches-galaxybook-ec/ that the kernel tree (HEAD) does not
# have yet, applied to a temporary copy, and install it (previous module kept
# as .prev). Then regenerate Fedora's initramfs for that kernel (keeps .prev)
# and remind to sync Arch.
# Run as your user on Fedora:
#
#   bash install/update-galaxybook-ec-module.sh [TREE]     (default TREE: ~/src/patchwork)
#
# Experiments: GBEC_EXTRA_PATCHES="path/to/a.patch ..." applies those after
# patches-galaxybook-ec/ (e.g. patches-experimental/0003-samsung-galaxybook-ec-*.patch).
#
# Rollback: copy the .prev files back, or boot the "(other)" Fedora kernel.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
TREE=${1:-$HOME/src/patchwork}
cd "$TREE"
K=$(make -s LOCALVERSION= kernelrelease)
DIR=drivers/platform/arm64
KO=/usr/lib/modules/$K/kernel/$DIR/samsung-galaxybook-ec.ko
IMG=/boot/initramfs-$K.img

[ -e /etc/fedora-release ] || { echo "Run this on Fedora." >&2; exit 1; }
[ -e "$KO" ] || { echo "No $KO: is $K (from $TREE) installed?" >&2; exit 1; }
[ "$K" = "$(uname -r)" ] && echo "Note: $K is running; the new module is used from the next boot."

echo "== 1. patches (on a copy of the committed driver; the tree is not modified)"
# Start from the driver as committed in the tree (HEAD), so reruns always
# begin from the same source: patches already committed there are detected
# and skipped, the others applied in order to the copy.
B=$(mktemp -d)
trap 'rm -rf "$B"' EXIT
git show HEAD:$DIR/samsung-galaxybook-ec.c > "$B/samsung-galaxybook-ec.c"
for p in "$REPO"/drivers/anatase/patches-galaxybook-ec/*.patch ${GBEC_EXTRA_PATCHES:-}; do
    if patch -s -p1 -d "$B" --dry-run -R -f -i "$p" >/dev/null 2>&1; then
        echo "   already in the tree's HEAD: ${p##*/}"
    else
        patch -s -p1 -d "$B" --dry-run -f -i "$p" >/dev/null ||
            { echo "   does not apply: ${p##*/}" >&2; exit 1; }
        patch -s -p1 -d "$B" -f -i "$p"
        echo "   applied: ${p##*/}"
    fi
done
rm -f "$B"/*.orig

echo "== 2. build samsung-galaxybook-ec.ko"
# As an external module against the configured tree: a single in-tree target
# (make $DIR/samsung-galaxybook-ec.ko) only resolves symbols against vmlinux, and this
# driver needs exports from other modules (power_supply, platform_profile).
echo 'obj-m := samsung-galaxybook-ec.o' > "$B/Makefile"
make -s LOCALVERSION= M="$B" modules
modinfo -F vermagic "$B/samsung-galaxybook-ec.ko"
[ "$(modinfo -F vermagic "$B/samsung-galaxybook-ec.ko" | cut -d' ' -f1)" = "$K" ] ||
    { echo "vermagic does not match $K, not installing." >&2; exit 1; }

echo "== 3. install (old module kept as .prev)"
sudo -v
sudo cp -p "$KO" "$KO.prev"
sudo install -m 644 "$B/samsung-galaxybook-ec.ko" "$KO"
sudo depmod "$K"

echo "== 4. Fedora initramfs for $K (old one kept as .prev)"
sudo cp -p "$IMG" "$IMG.prev"
sudo dracut -f --kver "$K"
if (( $(sudo lsinitrd "$IMG" 2>/dev/null | grep -c samsung-galaxybook-ec || true) > 0 )); then
    echo "   samsung-galaxybook-ec is in the initramfs"
else
    echo "   samsung-galaxybook-ec is not in the initramfs (loaded from disk)"
fi

echo
echo "Done. From Arch: bash $REPO/install/arch/fedora-shell.sh --sync-modules $K"
echo "Then reboot. Rollback: sudo cp -p $KO.prev $KO; sudo cp -p $IMG.prev $IMG; sudo depmod $K"
