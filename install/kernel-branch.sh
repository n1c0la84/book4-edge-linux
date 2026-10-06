#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Make the kernel we run reproducible and public: a branch book4/<series> in
# the Anatase kernel tree with Anatase's base plus our patches as commits
# (device tree: dts/patches, git am; samsung-emuec: drivers/anatase/patches)
# and our kernel config as arch/arm64/configs/book4_edge_defconfig; then
# (optionally) push it to a GitHub fork of anatase-org/patchwork.
# Our patches stay files in this repo too, and each one goes to Anatase as
# well: the branch should only carry what Anatase has not taken yet.
# Run as your user on Fedora (or in install/arch/fedora-shell.sh):
#
#   bash install/kernel-branch.sh [TREE]            build the branch locally
#   bash install/kernel-branch.sh [TREE] --push     also fork (once) and push
#
# TREE defaults to ~/src/patchwork. BASE (default: the Anatase commit the
# running 7.2.7-book4 was built from) can be overridden: BASE=<commit>.
set -euo pipefail
export GIT_PAGER=cat     # no pager inside the container
REPO=$(cd "$(dirname "$0")/.." && pwd)
TREE=$HOME/src/patchwork
PUSH=0
for a in "$@"; do
    case "$a" in
        --push) PUSH=1 ;;
        *) TREE=$a ;;
    esac
done
BASE=${BASE:-2ad788424}               # anatase-org/patchwork anatase-7.2, see docs/kernel.md
SERIES=${SERIES:-7.2}
BRANCH=book4/$SERIES
FORK_NAME=${FORK_NAME:-linux-book4-edge}
DIR=drivers/usb/typec
cd "$TREE"
AUTHOR="$(git config user.name) <$(git config user.email)>"
[ "$AUTHOR" != " <>" ] || { echo "Set git user.name/user.email (in $TREE or globally) first." >&2; exit 1; }

echo "== 0. tree $TREE"
git rev-parse --verify -q "$BASE^{commit}" >/dev/null || { echo "Base $BASE not in this tree (git fetch origin first)." >&2; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] ||
    { echo "Uncommitted changes in $TREE; commit or stash them first:" >&2; git status --short --untracked-files=no >&2; exit 1; }
[ -e .config ] || { echo "No .config in $TREE (the config the installed kernel was built with)." >&2; exit 1; }
echo "   base $(git log -1 --format='%h %s' "$BASE")"
echo "   current branch $(git branch --show-current) at $(git log -1 --format=%h)"
EXISTS=0
if git rev-parse --verify -q "$BRANCH" >/dev/null; then
    (( PUSH )) || { echo "$BRANCH exists already; rename or delete it to rebuild it (or --push it)." >&2; exit 1; }
    EXISTS=1
    echo "   $BRANCH exists: pushing it as it is"
fi
SAVED=$(mktemp)
cp .config "$SAVED"
trap 'rm -f "$SAVED"' EXIT
prev=$(git branch --show-current)

if (( ! EXISTS )); then
echo "== 1. $BRANCH from $BASE"
git switch -q -c "$BRANCH" "$BASE"

echo "== 2. device tree patches (git am)"
git am -q --3way "$REPO"/dts/patches/*.patch ||
    { echo "A device tree patch did not apply (git am --abort; git switch $prev; git branch -D $BRANCH)." >&2; exit 1; }
git log --oneline "$BASE"..HEAD

echo "== 3. samsung-emuec patches"
for p in "$REPO"/drivers/anatase/patches/*.patch; do
    git apply -p1 --directory=$DIR "$p"     # plain diffs of the one driver file
    subject=$(sed -n 's/^Subject: \[PATCH[^]]*\] //p' "$p" | head -1)
    body=$(awk 'f && /^---$/ {exit} f {print} /^Subject:/ {f=1}' "$p" | sed '1{/^$/d}')
    git commit -q -a --author="$AUTHOR" -m "$subject" -m "$body" -m "From book4-edge-linux: drivers/anatase/patches/${p##*/}"
    echo "   $(git log -1 --format='%h %s')"
done

echo "== 4. config as arch/arm64/configs/book4_edge_defconfig"
cp "$SAVED" .config
make -s LOCALVERSION= savedefconfig
mv defconfig arch/arm64/configs/book4_edge_defconfig
git add arch/arm64/configs/book4_edge_defconfig
git commit -q --author="$AUTHOR" -m "arm64: configs: add book4_edge_defconfig" \
    -m "Configuration of the 7.2.7-book4 kernel running on the Samsung Galaxy Book4 Edge 14\" (NP940XMA): make book4_edge_defconfig reproduces it."
cp "$SAVED" .config   # leave the tree's .config as it was
echo "   $(git log -1 --format='%h %s')"

echo "== 4b. .github/README.md (what GitHub shows for the fork; the kernel's README stays)"
mkdir -p .github
cp "$REPO/tools/kernel/fork-README.md" .github/README.md
git add .github/README.md
git commit -q --author="$AUTHOR" -m "README for the book4 branch (.github/README.md)" \
    -m "What this fork is, its patches and their upstream status, how to build it; GitHub shows .github/README.md in place of the kernel's README."
echo "   $(git log -1 --format='%h %s')"

echo "== 5. check against what was built"
if [ -n "$prev" ]; then
    echo "   differences to $prev in the driver and the device tree (expect none or only our newer patches):"
    git diff --stat "$prev" "$BRANCH" -- $DIR/samsung-emuec.c arch/arm64/boot/dts/qcom/ | tail -5
fi
fi   # ! EXISTS
git log --oneline "$BASE".."$BRANCH"

if (( PUSH )); then
    echo "== 6. GitHub fork and push (public)"
    me=$(gh api user --jq .login)
    if ! gh repo view "$me/$FORK_NAME" >/dev/null 2>&1; then
        read -r -p "Create the public fork $me/$FORK_NAME of anatase-org/patchwork? Type YES: " ok
        [ "$ok" = YES ] || { echo "Not pushed."; exit 0; }
        gh repo fork anatase-org/patchwork --clone=false --fork-name "$FORK_NAME"
    fi
    git remote get-url book4 >/dev/null 2>&1 || git remote add book4 "https://github.com/$me/$FORK_NAME.git"
    git push book4 "$BRANCH"
    gh repo edit "$me/$FORK_NAME" --default-branch "$BRANCH" \
        --description "Anatase kernel + Samsung Galaxy Book4 Edge 14\" patches (see n1c0la84/book4-edge-linux)"
    echo "   https://github.com/$me/$FORK_NAME/tree/$BRANCH"
fi
git switch -q "${prev:-$BRANCH}"
echo "Done. Branch $BRANCH; build it with: git switch $BRANCH && make LOCALVERSION= book4_edge_defconfig"
