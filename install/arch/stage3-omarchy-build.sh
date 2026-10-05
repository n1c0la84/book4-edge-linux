#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Arch stage 3a: build Omarchy 4.0.4 (omarchy, omarchy-settings,
# omarchy-keyring) from Omarchy's own PKGBUILDs, for aarch64. On aarch64
# those recipes leave out the Limine/snapper boot stack. One change:
# ttf-jetbrains-mono-nerd-basic is not in Arch Linux ARM, use
# ttf-jetbrains-mono-nerd. Also writes the list of Omarchy default packages
# that exist in Arch Linux ARM. Run as your user on Arch.
set -euo pipefail
SRC=${OMARCHY_BUILD_SRC:-$HOME/src}
BUILD=$SRC/omarchy-build
PKGS_COMMIT=31b8fdb3ad96fa89a6ab4492be9b7e59eb7af080   # omacom/omarchy-pkgs, 3 Oct 2026

echo "== build tools"
sudo pacman -S --needed --noconfirm base-devel imagemagick git

echo "== Omarchy PKGBUILDs (omacom/omarchy-pkgs @ ${PKGS_COMMIT:0:7})"
mkdir -p "$SRC"
if [[ ! -d $SRC/omarchy-pkgs ]]; then
  git clone -q --filter=blob:none --sparse https://github.com/omacom/omarchy-pkgs.git "$SRC/omarchy-pkgs"
fi
git -C "$SRC/omarchy-pkgs" fetch -q origin "$PKGS_COMMIT"
git -C "$SRC/omarchy-pkgs" checkout -q "$PKGS_COMMIT"
git -C "$SRC/omarchy-pkgs" sparse-checkout set pkgbuilds/omarchy pkgbuilds/omarchy-settings pkgbuilds/omarchy-keyring

mkdir -p "$BUILD"
cp -r "$SRC"/omarchy-pkgs/pkgbuilds/{omarchy,omarchy-settings,omarchy-keyring} "$BUILD/"
sed -i "s/'ttf-jetbrains-mono-nerd-basic'/'ttf-jetbrains-mono-nerd' # book4: -basic is not in Arch Linux ARM/" \
  "$BUILD/omarchy/PKGBUILD"
grep -q "'ttf-jetbrains-mono-nerd' # book4" "$BUILD/omarchy/PKGBUILD"

# The omarchy package is built from the same pinned commit plus our patches
# (userspace/omarchy/patches/, e.g. battery detection), through the
# PKGBUILD's OMARCHY_SRC hook; pkgrel 2 so it replaces a stock 4.0.4-1.
REPO=$(cd "$(dirname "$0")/../.." && pwd)
COMMIT=$(sed -n "s/^_commit='\(.*\)'/\1/p" "$BUILD/omarchy/PKGBUILD")
PATCHED=$SRC/omarchy-book4
echo "== Omarchy source ${COMMIT:0:7} + our patches -> $PATCHED"
[[ -d $PATCHED/.git ]] || git clone -q --filter=blob:none https://github.com/basecamp/omarchy.git "$PATCHED"
git -C "$PATCHED" fetch -q origin "$COMMIT"
git -C "$PATCHED" checkout -q --force --detach "$COMMIT"
git -C "$PATCHED" clean -qfd
for patch in "$REPO"/userspace/omarchy/patches/*.patch; do
  git -C "$PATCHED" apply "$patch"
  echo "   applied ${patch##*/}"
done
sed -i 's/^pkgrel=1$/pkgrel=2/' "$BUILD/omarchy/PKGBUILD"

# -d: runtime dependencies (gum, plymouth, quickshell, ...) are resolved by
# pacman at install time, not needed to build.
for p in omarchy-keyring omarchy-settings; do
  echo "== makepkg $p"
  (cd "$BUILD/$p" && makepkg -fd)
done
echo "== makepkg omarchy (patched source)"
(cd "$BUILD/omarchy" && OMARCHY_SRC=$PATCHED makepkg -fd)

echo "== Omarchy default packages available in Arch Linux ARM"
base=$BUILD/omarchy/src/omarchy/install/omarchy-base.packages
: >"$BUILD/avail.list"
missing=()
while read -r p; do
  if pacman -Sp --print-format %n "$p" >/dev/null 2>&1; then
    echo "$p" >>"$BUILD/avail.list"
  else
    missing+=("$p")
  fi
done < <(grep -vE '^\s*#|^\s*$' "$base" | awk '{print $1}')
echo "available: $(wc -l <"$BUILD/avail.list")   missing: ${missing[*]}"
ls "$BUILD"/*/*.pkg.tar.*
