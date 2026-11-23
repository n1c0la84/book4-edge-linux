#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# A private pacman repository [book4-private] on the home server's share
# (Unraid "storage", mounted at /mnt/storage), for the package that must never
# be published: book4-edge-firmware (Windows/Qualcomm/Samsung files, this
# laptop's sensor calibration). Nothing leaves the home network. Saves
# re-running install/arch/firmware-stage.sh after a reinstall.
#
#   bash install/arch/book4-private.sh publish [NAME]   newest build of packages/NAME (default book4-edge-firmware)
#   bash install/arch/book4-private.sh list
#   bash install/arch/book4-private.sh install [NAME]   sudo pacman -U the newest stored build
#
# Deliberately not in pacman.conf: away from home the share is unreachable,
# and an unreachable repository makes `pacman -Syu` fail ("failed to
# synchronize all databases"). To use it as a repository by hand:
#   [book4-private]  SigLevel = Optional TrustAll  Server = file:///mnt/storage/BACKUPS/book4-private
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
DIR=${BOOK4_PRIVATE_DIR:-/mnt/storage/BACKUPS/book4-private}
DB=book4-private

die() { echo "book4-private: $*" >&2; exit 1; }
share() { ls "${DIR%/*}" >/dev/null 2>&1 || die "the share is not reachable (${DIR%/*}); at home?"; mkdir -p "$DIR"; }
newest() { ls -t "$1"/$2-[0-9r]*.pkg.tar.* 2>/dev/null | grep -v '\.sig$' | head -1; }

case "${1:-}" in
publish)
    name=${2:-book4-edge-firmware}
    pkg=$(newest "$repo/packages/$name" "$name") || true
    [ -n "$pkg" ] || die "no build in packages/$name (makepkg -f there first)"
    share
    cp -v "$pkg" "$DIR/"
    # repo-add in a local directory: SMB shares may refuse the .db symlinks;
    # store plain copies under the names pacman asks for.
    w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
    cp "$DIR"/*.pkg.tar.* "$w/" 2>/dev/null || true
    [ -e "$DIR/$DB.db.tar.gz" ] && cp "$DIR/$DB.db.tar.gz" "$DIR/$DB.files.tar.gz" "$w/" 2>/dev/null || true
    (cd "$w" && repo-add -q -R "$DB.db.tar.gz" "${pkg##*/}")
    # -R removed the older build from $w; mirror that on the share
    for f in "$DIR"/*.pkg.tar.*; do [ -e "$w/${f##*/}" ] || rm -v "$f"; done
    for n in db files; do
        cp "$w/$DB.$n.tar.gz" "$DIR/$DB.$n.tar.gz"
        cp "$w/$DB.$n.tar.gz" "$DIR/$DB.$n"
    done
    echo "book4-private: $DIR"; ls -l "$DIR" ;;
list)
    share
    tar -tzf "$DIR/$DB.db.tar.gz" 2>/dev/null | sed -n 's|/$||p' || echo "(empty)" ;;
install)
    name=${2:-book4-edge-firmware}
    share
    pkg=$(newest "$DIR" "$name") || true
    [ -n "$pkg" ] || die "no $name on the share"
    sudo pacman -U --needed "$pkg" ;;
*)
    sed -n '3,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 1 ;;
esac
