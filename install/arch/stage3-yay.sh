#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# AUR helper `yay` (the one Omarchy's scripts call), built from the AUR with
# makepkg. First puts our hand-installed packages in IgnorePkg, so neither
# `yay -Syu` nor `omarchy update` (yay -Sua) tries to replace them with AUR
# packages (AUR google-chrome is x86_64-only; mise-bin, omarchy* are ours).
# Arch stage 3 (optional, after stage3-omarchy-user.sh). Run as your user on Arch.
set -euo pipefail
if (( EUID == 0 )); then
  echo "Run as your user, not as root." >&2
  exit 1
fi
IGNORE="omarchy omarchy-settings omarchy-keyring mise-bin google-chrome"
SRC=$HOME/src/yay

echo "== 1. IgnorePkg for the hand-installed packages"
sudo cp -n /etc/pacman.conf /etc/pacman.conf.book4-pre-yay
if ! grep -q '^IgnorePkg' /etc/pacman.conf; then
  sudo sed -i "s|^#IgnorePkg   =\$|# book4: installed by hand (local builds, Omarchy aarch64 repo); update them by hand\nIgnorePkg = $IGNORE|" /etc/pacman.conf
fi
grep -n '^IgnorePkg' /etc/pacman.conf || { echo "IgnorePkg not set, stopping." >&2; exit 1; }

echo "== 2. build tools"
sudo pacman -S --needed --noconfirm base-devel git go

echo "== 3. yay from the AUR"
if [[ -d $SRC/.git ]]; then
  git -C "$SRC" pull -q --ff-only
else
  git clone -q https://aur.archlinux.org/yay.git "$SRC"
fi
grep -E '^(pkgver|arch|source)=' "$SRC/PKGBUILD"
(cd "$SRC" && makepkg -si --needed --noconfirm)

echo "== checks"
yay --version
echo "AUR updates yay would offer (ignored packages are skipped):"
yay -Qua || true
