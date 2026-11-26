#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Installs book4-update (userspace/update/book4-update) and the Omarchy
# post-update verification hook (userspace/update/book4-post-update-check):
#   ~/.local/bin/book4-update -> this repo's copy (a symlink, so a git pull
#   updates it)
#   ~/.config/omarchy/hooks/post-update.d/90-book4-verify.sh -> repo copy
# Run on Arch as your user:  bash install/arch/update.sh [undo]
set -euo pipefail
dir=$(cd "$(dirname "$0")/../../userspace/update" && pwd)
src=$dir/book4-update
hook_src=$dir/book4-post-update-check
bin=$HOME/.local/bin/book4-update
hook=$HOME/.config/omarchy/hooks/post-update.d/90-book4-verify.sh

[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
if [[ ${1:-} == undo ]]; then
    rm -f "$bin" "$hook"
    echo "Removed $bin and $hook."
    exit 0
fi
chmod +x "$src" "$hook_src"
mkdir -p "$(dirname "$bin")" "$(dirname "$hook")"
ln -sfn "$src" "$bin"
ln -sfn "$hook_src" "$hook"
echo "Installed: $bin -> $src"
echo "Installed: $hook -> $hook_src"
echo "Try: book4-update --check"
