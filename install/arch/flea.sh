#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Builds and installs Flea (github.com/thisisgm/flea), the Omarchy file
# manager. Upstream ships it only in the Omarchy Package Repository, which is
# x86_64-only, so `omarchy pkg add flea` fails here ("target not found"), and
# `omarchy update` never updates it. Its PKGBUILD lists aarch64 and builds
# natively: this script fetches the PKGBUILD from tag v<version>, fills in
# the release tarball's sha256 (upstream keeps zeros in git) and runs makepkg
# with the rustup cargo (--nodeps) and without the long test suite (--nocheck).
# Then pacman installs the runtime deps and the package (asks for sudo).
# Run on Arch as your user:  bash install/arch/flea.sh [version]   (default 0.4.0)
# Then, in a terminal in your session:  flea --default
set -euo pipefail
ver=${1:-0.4.0}
url=https://github.com/thisisgm/flea
work=${XDG_CACHE_HOME:-$HOME/.cache}/book4-flea/$ver

[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
command -v cargo >/dev/null || { echo "Needs cargo (rustup)." >&2; exit 1; }

mkdir -p "$work" && cd "$work"
curl -fsSL -o PKGBUILD "https://raw.githubusercontent.com/thisisgm/flea/v$ver/PKGBUILD"
curl -fsSL -o "flea-v$ver.tar.gz" "$url/releases/download/v$ver/flea-v$ver.tar.gz"
grep -q "^pkgver=$ver\$" PKGBUILD || { echo "PKGBUILD at v$ver is not pkgver=$ver." >&2; exit 1; }
sha=$(sha256sum "flea-v$ver.tar.gz" | cut -d' ' -f1)
sed -i "s/'0\{64\}'/'$sha'/" PKGBUILD

makepkg --nodeps --nocheck -f
# The runtime deps (cargo, git, pkgconf are build-only and come from rustup/base).
mapfile -t deps < <(bash -c 'source ./PKGBUILD; pacman -T "${depends[@]}"' || true)
if ((${#deps[@]})); then
  sudo pacman -S --needed "${deps[@]}"
fi
sudo pacman -U flea-"$ver"-*-aarch64.pkg.tar.*
