#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Installs book4-update (userspace/update/book4-update), this machine's
# replacement for `omarchy update`: cache prune, btrfs snapshot of the arch
# subvolume, pacman -Syu, yay -Sua, mise up, then post-update checks.
#   ~/.local/bin/book4-update -> this repo's copy (a symlink, so a git pull
#   updates it)
# Run on Arch as your user:  bash install/arch/update.sh [undo]
set -euo pipefail
src=$(cd "$(dirname "$0")/../../userspace/update" && pwd)/book4-update
bin=$HOME/.local/bin/book4-update

[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
if [[ ${1:-} == undo ]]; then
    rm -f "$bin"
    echo "Removed $bin."
    exit 0
fi
chmod +x "$src"
mkdir -p "$(dirname "$bin")"
ln -sfn "$src" "$bin"
echo "Installed: $bin -> $src"
echo "Try: book4-update --check"
