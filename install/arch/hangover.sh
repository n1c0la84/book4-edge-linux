#!/usr/bin/env bash
# Hangover: Wine 11 built for ARM64 with FEX (x86-64, via ARM64EC) and box64
# (32-bit x86, via WoW64) inside, so x86 Windows programs run on the Book4.
# Bottles cannot do this on aarch64 (its runners are x86_64 builds).
#
# No root needed.  Unpacks the upstream Ubuntu 26.04 arm64 debs into
# ~/.local/opt/hangover-$VER (Wine is relocatable; every library it needs is
# already on the Omarchy install), creates the prefix
# ~/.local/share/wineprefixes/hangover and installs the `hwine` launcher.
# Needs: gh (or curl), bsdtar; 4K pages (Wine does not run on 16K kernels).
#
# Usage: install/arch/hangover.sh [version]     (default 11.16)
#        hwine prog.exe | hwine winecfg | hwine winetricks <verb>
set -euo pipefail

VER=${1:-11.16}
DIST=ubuntu2604_resolute
OPT="$HOME/.local/opt/hangover-$VER"
PREFIX="$HOME/.local/share/wineprefixes/hangover"

[ "$(getconf PAGESIZE)" = 4096 ] || { echo "Wine needs a 4K-page kernel" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tarball="hangover_${VER}_${DIST}_arm64.tar"
if command -v gh >/dev/null; then
  gh release download "hangover-$VER" -R AndreRH/hangover -p "$tarball" -D "$work"
else
  curl -fL -o "$work/$tarball" \
    "https://github.com/AndreRH/hangover/releases/download/hangover-$VER/$tarball"
fi
tar xf "$work/$tarball" -C "$work"

mkdir -p "$OPT"
for deb in "$work"/hangover-*.deb; do
  d="${deb%.deb}"; mkdir -p "$d"
  (cd "$d" && bsdtar xf "$deb" && bsdtar xf data.tar.*)
  cp -a "$d/usr/." "$OPT/"
done

mkdir -p "$HOME/.local/bin"
cat >"$HOME/.local/bin/hwine" <<EOF
#!/bin/sh
# Hangover (Wine for ARM64 + FEX/box64): run x86/x64 Windows programs.
# Installed by book4-edge-linux install/arch/hangover.sh.
# Usage: hwine prog.exe | hwine winecfg | hwine winetricks <verb>
# Another prefix: HWINE_PREFIX=dir hwine ...
export WINEPREFIX="\${HWINE_PREFIX:-$PREFIX}"
export WINEDEBUG="\${WINEDEBUG:--all}"
H="$OPT/bin"
case "\$1" in
  winecfg|regedit|wineboot|wineserver|winefile|notepad|msiexec|winetricks) c="\$1"; shift
    [ "\$c" = winetricks ] && { WINE="\$H/wine" WINESERVER="\$H/wineserver" exec winetricks "\$@"; }
    exec "\$H/\$c" "\$@";;
esac
exec "\$H/wine" "\$@"
EOF
chmod +x "$HOME/.local/bin/hwine"

mkdir -p "$(dirname "$PREFIX")"
"$HOME/.local/bin/hwine" wineboot -u
"$HOME/.local/bin/hwine" --version
echo "Prefix: $PREFIX   Run programs with: hwine prog.exe"
