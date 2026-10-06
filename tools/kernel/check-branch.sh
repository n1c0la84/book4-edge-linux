#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Does the kernel branch (default book4/7.2) reproduce what this machine runs?
#  1. samsung-emuec.c on the branch vs. the installed module's source: the
#     branch the kernel was built from (default book4/pd-retry) plus the
#     driver patches applied by install/update-emuec-module.sh afterwards.
#  2. The DTB built from the branch vs. the default DTB in /boot
#     (/etc/book4/default-dtb), both decompiled.
# Read-only for the tree (switches branches only if needed and back; aborts
# if there are uncommitted changes). Run in Fedora or through
# install/arch/fedora-shell.sh.
set -euo pipefail
export GIT_PAGER=cat
REPO=$(cd "$(dirname "$0")/../.." && pwd)
TREE=${TREE:-$HOME/src/patchwork}
BRANCH=${BRANCH:-book4/7.2}
BUILT_FROM=${BUILT_FROM:-book4/pd-retry}
DRV=drivers/usb/typec/samsung-emuec.c
DTBNAME=x1e80100-samsung-galaxy-book4-edge-14.dtb
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cd "$TREE"
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "Uncommitted changes in $TREE." >&2; exit 1; }
start=$(git branch --show-current)
rc=0

echo "== 1. $DRV: $BRANCH vs. $BUILT_FROM + patches 0002.. (the installed module)"
mkdir "$T/drv"
git show "$BUILT_FROM:$DRV" > "$T/drv/samsung-emuec.c"     # the patches use a/samsung-emuec.c
for p in "$REPO"/drivers/anatase/patches/*.patch; do
    if patch -s -p1 -d "$T/drv" --dry-run -R -f -i "$p" >/dev/null 2>&1; then
        echo "   already in $BUILT_FROM: ${p##*/}"
    else
        patch -s -p1 -d "$T/drv" -f --no-backup-if-mismatch -i "$p" || { echo "   ${p##*/} does not apply" >&2; exit 1; }
        echo "   + ${p##*/}"
    fi
done
cp "$T/drv/samsung-emuec.c" "$T/built.c"
if git show "$BRANCH:$DRV" | diff -u "$T/built.c" - >"$T/drv.diff"; then
    echo "   IDENTICAL"
else
    echo "   DIFFERENT:"; sed -n 1,40p "$T/drv.diff"; rc=1
fi

echo "== 2. $DTBNAME from $BRANCH vs. the default DTB in /boot"
read -r kver dtbpath < /etc/book4/default-dtb
echo "   default: $kver $dtbpath"
[ "$start" = "$BRANCH" ] || git switch -q "$BRANCH"
# New Kconfig symbols would make the build stop and ask: take the defaults.
make -s LOCALVERSION= olddefconfig >/dev/null
make -s LOCALVERSION= "qcom/$DTBNAME"
# The kernel build compiles with dtc -@ (overlay symbols), which also gives
# every labelled node a phandle and so renumbers all references. The /boot
# DTB was compiled without -@ (and re-padded with -p 8192 by
# install/speakers-default.sh): compile the build's preprocessed source the
# same way, so equal sources give equal bytes.
cp "arch/arm64/boot/dts/qcom/.$DTBNAME.dts.tmp" "$T/branch.dts.tmp"
[ "$start" = "$BRANCH" ] || git switch -q "$start"
dtc -q -I dts -O dtb -o "$T/branch.dtb" "$T/branch.dts.tmp"
dtc -q -I dtb -O dtb -p 8192 -o "$T/branch.p.dtb" "$T/branch.dtb"
dtc -q -I dtb -O dtb -p 8192 -o "$T/boot.p.dtb" "/boot$dtbpath"
if cmp -s "$T/branch.p.dtb" "$T/boot.p.dtb"; then
    echo "   IDENTICAL (byte for byte; both compiled without -@)"
else
    dtc -q -I dtb -O dts -s "$T/boot.p.dtb" > "$T/boot.dts"
    dtc -q -I dtb -O dts -s "$T/branch.p.dtb" > "$T/branch.dts"
    diff -u "$T/boot.dts" "$T/branch.dts" > "$T/dtb.diff" || true
    echo "   DIFFERENT ($(grep -c '^[-+][^-+]' "$T/dtb.diff") changed lines):"
    sed -n 1,80p "$T/dtb.diff"; rc=1
fi
exit $rc
