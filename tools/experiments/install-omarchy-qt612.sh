#!/usr/bin/env bash
# Install omarchy 4.0.4-3: v4.0.4 + book4 battery fixes + backport of upstream
# b83d3df (qualify the Color singleton so the shell works on Qt 6.12).
# Run as yourself: bash ~/install-omarchy-qt612.sh
# Roll back: sudo pacman -U ~/src/omarchy-build/omarchy/omarchy-4.0.4-2-aarch64.pkg.tar.xz
set -euo pipefail

pkg=$HOME/src/omarchy-build/omarchy/omarchy-4.0.4-3-aarch64.pkg.tar.xz
[[ -r $pkg ]] || { echo "error: $pkg not found" >&2; exit 1; }

# omarchy is in IgnorePkg, so pacman asks "Install anyway?" — answer yes.
sudo pacman -U "$pkg"

pacman -Q omarchy
omarchy restart shell
