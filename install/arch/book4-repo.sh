#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# A local pacman repository [book4] for the Book4 layer's packages
# (packages/: linux-book4, book4-edge, book4-edge-boot, book4-edge-el2,
# book4-edge-firmware, fastrpc, libssc-book4, iio-sensor-proxy-book4,
# book4-sensors, libfprint-sdcp).
# It lives on this laptop only (the firmware package must never be
# published): /var/lib/book4-repo, owned by you so adding needs no root,
# declared in /etc/pacman.d/book4-repo.conf and included at the end of
# /etc/pacman.conf. Then `pacman -S book4-edge` works, and a newer build
# added here comes with `pacman -Syu` / `omarchy-update` like any update.
#
#   bash install/arch/book4-repo.sh setup        create it, add every built package, pacman -Sy
#   bash install/arch/book4-repo.sh add [NAME]   add the newest build of packages/NAME (default: all)
#   bash install/arch/book4-repo.sh list         what the repository holds
#   bash install/arch/book4-repo.sh undo         remove the Include and the repository
#
# Build first (makepkg -f in packages/NAME), then `add`; for the firmware,
# install/arch/firmware-stage.sh before makepkg. Unsigned packages: the
# repository is a local directory only root and you can write.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
R=/var/lib/book4-repo
DB=$R/book4.db.tar.gz
CONF=/etc/pacman.d/book4-repo.conf
NAMES=(linux-book4 book4-edge book4-edge-boot book4-edge-el2 book4-edge-firmware
       fastrpc libssc-book4 iio-sensor-proxy-book4 book4-sensors libfprint-sdcp)
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }

newest() {  # packages/NAME -> its newest built package files (main, and -headers for the kernel)
    local n=$1 d=$repo/packages/$1 f
    for f in $(ls -t "$d"/"$n"-[0-9r]*.pkg.tar.* 2>/dev/null | grep -v '\.sig$' | head -1) \
             $( [ "$n" = linux-book4 ] && ls -t "$d"/"$n"-headers-[0-9]*.pkg.tar.* 2>/dev/null | grep -v '\.sig$' | head -1); do
        echo "$f"
    done
}

add() {
    local files=() n f
    for n in "${@:-${NAMES[@]}}"; do
        mapfile -t got < <(newest "$n")
        [ ${#got[@]} -gt 0 ] || { echo "   $n: no build in packages/$n (makepkg -f there first)"; continue; }
        for f in "${got[@]}"; do cp -f "$f" "$R/"; files+=("$R/${f##*/}"); echo "   $n: ${f##*/}"; done
    done
    [ ${#files[@]} -gt 0 ] || { echo "nothing to add" >&2; return 1; }
    # -R drops the older file of a package from the directory, -n skips one already in
    repo-add -q -R -n "$DB" "${files[@]}"
}

case "${1:-}" in
setup)
    sudo -v
    echo "== 1. $R"
    sudo install -d -m 755 -o "$USER" -g "$(id -gn)" "$R"
    echo "== 2. packages"
    add
    echo "== 3. pacman.conf"
    printf '# Local Book4 layer packages (book4-edge-linux install/arch/book4-repo.sh)\n[book4]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$R" |
        sudo tee "$CONF" >/dev/null
    grep -qxF "Include = $CONF" /etc/pacman.conf ||
        printf '\n# book4-edge-linux: local repository [book4]\nInclude = %s\n' "$CONF" | sudo tee -a /etc/pacman.conf >/dev/null
    sudo pacman -Sy
    echo "== 4. what pacman sees"
    pacman -Sl book4 ;;
add)
    shift; add "$@"
    echo "Now: sudo pacman -Sy, then pacman -Syu (or omarchy-update) installs what is newer." ;;
list)
    pacman -Sl book4 2>/dev/null || tar -tzf "$DB" | sed -n 's|/$||p' ;;
undo)
    sudo sed -i "\|^# book4-edge-linux: local repository \[book4\]$|d; \|^Include = $CONF$|d" /etc/pacman.conf
    sudo rm -f "$CONF"
    echo "Include removed. The directory $R stays (remove it yourself if wanted); installed packages stay." ;;
*) sed -n '3,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 1 ;;
esac
