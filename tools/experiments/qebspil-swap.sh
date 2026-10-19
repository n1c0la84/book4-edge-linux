#!/usr/bin/env bash
# Put a qebspil variant on the ESP (\EFI\book4-el2\qebspilaa64.efi):
#   noproxy  test build without the UEFI proxy vote (QEBSPIL_NO_PROXY_VOTE=1)
#   proxy    the normal build (what esp-install.sh installs)
# Any boot. Run as yourself: bash ~/qebspil-swap.sh noproxy|proxy
set -euo pipefail
case "${1:-}" in
  noproxy) src=$HOME/src/ext/qebspil/out/qebspilaa64-noproxy.efi ;;
  proxy)   src=$HOME/src/ext/qebspil/out/qebspilaa64-proxy.efi ;;
  *) echo "usage: $0 noproxy|proxy" >&2; exit 1 ;;
esac
[ -s "$src" ] || { echo "error: $src missing" >&2; exit 1; }
sudo -v
esp=$(findmnt -rn -o TARGET -S /dev/sda1 | head -1 || true); own=
[ -n "$esp" ] || { esp=$(mktemp -d); own=1; sudo mount -o umask=0077,shortname=winnt /dev/sda1 "$esp"; }
sudo test -d "$esp/EFI/book4-el2" || { echo "error: \\EFI\\book4-el2 not on the ESP" >&2; exit 1; }
sudo install -m 600 "$src" "$esp/EFI/book4-el2/qebspilaa64.efi"
sudo cmp "$src" "$esp/EFI/book4-el2/qebspilaa64.efi" && echo "installed $1 variant ($(basename "$src"))"
sync; [ -n "$own" ] && { sudo umount "$esp"; rmdir "$esp"; } || true
