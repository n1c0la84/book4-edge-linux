#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Add or update .github/README.md (tools/kernel/fork-README.md) on the kernel
# branch and push it to the fork; GitHub shows it in place of the kernel's
# README. The tree is left on the branch it was on. Run in Fedora or through
# install/arch/fedora-shell.sh:
#
#   bash book4-edge-linux/tools/kernel/push-fork-readme.sh
set -euo pipefail
export GIT_PAGER=cat
REPO=$(cd "$(dirname "$0")/../.." && pwd)
TREE=${TREE:-$HOME/src/patchwork}
BRANCH=${BRANCH:-book4/7.2}
cd "$TREE"
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "Uncommitted changes in $TREE." >&2; git status --short --untracked-files=no >&2; exit 1; }
git remote get-url book4 >/dev/null || { echo "No remote 'book4' (run install/kernel-branch.sh --push first)." >&2; exit 1; }
start=$(git branch --show-current)
trap 'git switch -q "$start"' EXIT
git switch -q "$BRANCH"
mkdir -p .github
cp "$REPO/tools/kernel/fork-README.md" .github/README.md
git add -f .github/README.md
if git diff --cached --quiet; then
    echo ".github/README.md already up to date on $BRANCH"
else
    git commit -q -m "README for the book4 branch (.github/README.md)" \
        -m "What this fork is, its patches and their upstream status, how to build it. GitHub shows .github/README.md in place of the kernel's README."
    echo "committed: $(git log -1 --format='%h %s')"
fi
git push book4 "$BRANCH"
git log --oneline -3
