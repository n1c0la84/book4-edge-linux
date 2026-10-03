#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Google Chrome for aarch64 from Omarchy's aarch64 repo (not in Arch Linux ARM),
# then Omarchy's own Chrome setup. The repo is NOT added to pacman.conf, so
# Chrome does not update with `pacman -Syu`: rerun this with a newer version.
# Arch stage 3 (optional, after stage3-omarchy-user.sh). Run as your user on Arch.
set -euo pipefail
if (( EUID == 0 )); then
  echo "Run as your user, not as root." >&2
  exit 1
fi
PKG=https://pkgs.omarchy.org/stable/aarch64/google-chrome-154.0.8037.57-1-aarch64.pkg.tar.zst

echo "== 1. google-chrome (signature checked by pacman against the Omarchy key)"
sudo pacman -U --needed --noconfirm "$PKG"

echo "== 2. Omarchy's Chrome setup (policy directory, Wayland flags, theme colour)"
# Chrome is installed now, so its AUR step (yay, not present here) is skipped.
omarchy-install-browser chrome

pacman -Q google-chrome
google-chrome-stable --version
