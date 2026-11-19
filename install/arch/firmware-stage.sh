#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Stage the files of the local-only package book4-edge-firmware
# (packages/book4-edge-firmware) in a private directory outside the repo:
# ADSP, CDSP and GPU firmware from this laptop's own Windows driver store and
# tcblaunch.exe from WinSxS (sda3 mounted read-only), the rest from the
# copies installed here. Each
# file is picked by its checksum in packages/book4-edge-firmware/sha256sums.txt:
# Windows keeps several versions side by side (19 November: a newer
# qcdxkmsuc8380.mbn from 18 November, an older CDSP pair), and only the ones
# this machine runs are taken. Nothing here is published. Run as your user:
#
#   bash install/arch/firmware-stage.sh      then: cd packages/book4-edge-firmware && makepkg -f
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
sums=$repo/packages/book4-edge-firmware/sha256sums.txt
stage=${BOOK4_FW_STAGE:-$HOME/.local/share/book4-edge-firmware}
WIN=/dev/sda3
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
findmnt -rn -S "$WIN" >/dev/null && { echo "error: $WIN is mounted; unmount it first" >&2; exit 1; }
mkdir -p "$stage"; chmod 700 "$stage"

sudo -v
m=$(mktemp -d); sudo mount -t ntfs3 -o ro "$WIN" "$m"
trap 'sudo umount "$m"; rmdir "$m"' EXIT
R=$m/Windows/System32/DriverStore/FileRepository
sudo test -d "$R" || { echo "error: no driver store on $WIN" >&2; exit 1; }

missing=0
while read -r sum path src; do
    case "$sum" in ''|\#*) continue ;; esac
    dst=$stage/$path; name=${path##*/}
    if [ -e "$dst" ] && [ "$(sha256sum < "$dst" | cut -d' ' -f1)" = "$sum" ]; then echo "   have   $path"; continue; fi
    found=
    case "$src" in
    windows:*)
        while IFS= read -r -d '' c; do
            if [ "$(sudo sha256sum < "$c" | cut -d' ' -f1)" = "$sum" ]; then found=$c; break; fi
        done < <(sudo find "$R" -maxdepth 2 -ipath "*/${src#windows:}*/$name" -print0)
        ;;
    winsxs:*)
        while IFS= read -r -d '' c; do
            if [ "$(sudo sha256sum < "$c" | cut -d' ' -f1)" = "$sum" ]; then found=$c; break; fi
        done < <(sudo find "$m/Windows/WinSxS" -maxdepth 2 -ipath "*/${src#winsxs:}*/$name" -print0)
        ;;
    local)
        case "$path" in /*) c=$path ;; *) c=/usr/lib/firmware/updates/$path ;; esac
        [ -e "$c" ] && [ "$(sha256sum < "$c" | cut -d' ' -f1)" = "$sum" ] && found=$c
        ;;
    esac
    if [ -n "$found" ]; then
        install -D -m 644 /dev/null "$dst"; sudo cat "$found" > "$dst"
        echo "   staged $path  <- ${found#$m/}"
    else
        echo "   MISSING $path (no $src copy with the expected checksum)"; missing=1
    fi
done < "$sums"
[ $missing = 0 ] || { echo "error: some files are missing; nothing to package" >&2; exit 1; }
echo; echo "Staged in $stage ($(du -sh "$stage" | cut -f1)). Next:"
echo "   cd $repo/packages/book4-edge-firmware && makepkg -f"
echo "   sudo pacman -U --overwrite '/usr/lib/firmware/updates/*' book4-edge-firmware-*.pkg.tar.*"
