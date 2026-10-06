#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# dts/patches/0003 (tweeters) was made on the bare Anatase base, next to the
# camera patches 0001-0002, and conflicts with 0002 in the -14.dts: both add
# blocks at the same place (camera: &tlmm; tweeters: &swr0, &swr3). This
# applies 0001-0002 and 0003 on a temporary branch, keeps both blocks,
# checks that the DTB compiles, and prints 0003 rebased onto 0002 on stdout
# (everything else goes to stderr). The tree is left on the branch it was on.
# Run in Fedora, or from Arch through the container:
#
#   bash install/arch/fedora-shell.sh bash book4-edge-linux/tools/kernel/merge-dts-patches.sh > new-0003.patch
set -euo pipefail
export GIT_PAGER=cat     # no pager inside the container
REPO=$(cd "$(dirname "$0")/../.." && pwd)
TREE=${TREE:-$HOME/src/patchwork}
BASE=${BASE:-2ad788424}
TMP=tmp/dts-merge
F=arch/arm64/boot/dts/qcom/x1e80100-samsung-galaxy-book4-edge-14.dts
cd "$TREE"
exec 3>&1 1>&2          # stdout is for the patch only

[ -d .git/rebase-apply ] && { echo "aborting a paused git am"; git am --abort; }
start=$(git branch --show-current)
[ -n "$start" ] && [ "$start" != "$TMP" ] || { echo "Tree is not on a normal branch ($start)." >&2; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "Uncommitted changes in $TREE." >&2; git status --short --untracked-files=no >&2; exit 1; }
echo "tree on $start; temporary branch $TMP from $BASE"
git switch -q -C "$TMP" "$BASE"
trap 'git am --abort 2>/dev/null; git switch -q -f "$start"; git branch -q -D "$TMP" 2>/dev/null || true' EXIT

git am -q "$REPO"/dts/patches/0001-*.patch "$REPO"/dts/patches/0002-*.patch
if git am -q --3way "$REPO"/dts/patches/0003-*.patch; then
    echo "0003 applied without conflict"
else
    echo "resolving the known conflict in $F (keep camera &tlmm, then tweeter &swr0/&swr3)"
    perl -0pi -e 's/^<<<<<<< [^\n]*\n(.*?)^=======\n(.*?)^>>>>>>> [^\n]*\n/$1\t};\n};\n\n$2/sm' "$F"
    ! grep -nE '^(<<<<<<<|=======|>>>>>>>)' "$F" || { echo "conflict markers left" >&2; exit 1; }
    [ -z "$(git diff --name-only --diff-filter=U | grep -vx "$F")" ] || { echo "conflicts in other files" >&2; exit 1; }
    git add "$F"
    GIT_EDITOR=true git am --continue
fi
make -s LOCALVERSION= qcom/x1e80100-samsung-galaxy-book4-edge-14.dtb
echo "DTB compiles"
git --no-pager log --oneline "$BASE"..HEAD
git --no-pager format-patch -1 --stdout HEAD >&3
