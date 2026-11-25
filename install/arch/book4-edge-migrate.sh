#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Move this machine from the script-installed Book4 layer to the packages
# book4-edge and book4-edge-boot (packages/, ROADMAP "Fresh install" 4):
#   1. build both packages if needed (makepkg)
#   2. pacman -U them; files the scripts put at the same paths (UCM, sleep
#      log, /etc/keyd, UPower, mkinitcpio.conf.d) are taken over (--overwrite)
#   3. the copies the scripts put elsewhere (/usr/local, /etc, ~/.config,
#      ~/.local/bin) are backed up to ~/book4-edge-migrated-<time>/, then
#      removed if the package has the same content (units: same after the
#      path rewrite); a copy that differs is kept and reported
#   4. units re-enabled from /usr/lib (system and user)
# Run as your user on Arch:  bash install/arch/book4-edge-migrate.sh
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
if findmnt -rn -S /dev/sda4 >/dev/null; then echo "error: /dev/sda4 (/boot) is mounted; unmount it first" >&2; exit 1; fi

echo "== 1. packages"
pkgs=()
for p in book4-edge book4-edge-boot; do
    d=$repo/packages/$p
    f=$(ls -t "$d"/$p-r*.pkg.tar.* 2>/dev/null | head -1 || true)
    if [ -z "$f" ]; then (cd "$d" && makepkg -f --noconfirm >/dev/null); f=$(ls -t "$d"/$p-r*.pkg.tar.* | head -1); fi
    echo "   $f"; pkgs+=("$f")
done

echo "== 2. pacman -U"
sudo -v
ow=()
for f in usr/share/alsa/ucm2/Qualcomm/x1e80100/Samsung-GalaxyBook4Edge.conf \
         usr/share/alsa/ucm2/Qualcomm/x1e80100/Samsung-GalaxyBook4Edge-HiFi.conf \
         'usr/share/alsa/ucm2/conf.d/x1e80100/SAMSUNGELECTRONICSCO.LTD.-GalaxyBook4Edge-2.1-NP940XMA_KB1IT.conf' \
         usr/lib/systemd/system-sleep/book4-sleep-log etc/keyd/book4.conf \
         etc/UPower/UPower.conf.d/70-book4.conf etc/mkinitcpio.conf.d/book4.conf; do
    ow+=(--overwrite "/$f")
done
sudo pacman -U --noconfirm "${ow[@]}" "${pkgs[@]}"
pacman -Qkk book4-edge book4-edge-boot 2>&1 | tail -2 | sed 's/^/   /'

echo "== 3. superseded copies"
bk=$HOME/book4-edge-migrated-$(date +%Y%m%d-%H%M%S); mkdir -p "$bk"
norm() { sed -e 's|/usr/local/sbin/|/usr/lib/book4/|g' -e 's|/usr/local/bin/|/usr/lib/book4/|g' \
             -e 's|%h/\.local/bin/|/usr/lib/book4/|g' -e 's|/usr/local/lib/book4/el2-sleep|/usr/lib/book4/book4-el2-sleep|g' \
             -e 's|/usr/local/lib/book4/|/usr/lib/book4/|g' "$1"; }
kept=()
retire() {  # old copy, packaged file, [user]
    local old=$1 new=$2 s=sudo
    [ "${3:-}" = user ] && s=
    $s test -e "$old" || return 0
    $s cp -a "$old" "$bk/$(echo "${old#/}" | tr / _)"
    if [ -e "$new" ] && cmp -s <($s cat "$old" | norm /dev/stdin) <(norm "$new"); then
        $s rm -f "$old"; echo "   removed $old"
    elif [ -e "$new" ] && cmp -s <($s sed -n '/^[^#]/p' "$old" | norm /dev/stdin) <(sed -n '/^[^#]/p' "$new" | norm /dev/stdin); then
        $s rm -f "$old"; echo "   removed $old (only comments differed)"
    else
        kept+=("$old"); echo "   KEPT $old (differs from $new)"
    fi
}
replace() {  # old copy the package supersedes whatever its content (it would shadow it)
    sudo test -e "$1" || return 0
    sudo cp -a "$1" "$bk/$(echo "${1#/}" | tr / _)"; sudo rm -f "$1"; echo "   replaced $1"
}
# system units: disable the /etc copy first (its wants/ links), enable again below
sysunits=(book4-bt-addr book4-fingerprint-import book4-live-log book4-el2-sleep)
for u in "${sysunits[@]}"; do
    [ -e "/etc/systemd/system/$u.service" ] || continue
    sudo systemctl disable -q "$u.service" 2>/dev/null || true
    retire "/etc/systemd/system/$u.service" "/usr/lib/systemd/system/$u.service"
done
retire /usr/local/sbin/book4-bt-addr            /usr/lib/book4/book4-bt-addr
retire /usr/local/sbin/book4-fingerprint-import /usr/lib/book4/book4-fingerprint-import
retire /usr/local/bin/book4-live-log            /usr/lib/book4/book4-live-log
retire /usr/local/lib/book4/el2-sleep           /usr/lib/book4/book4-el2-sleep
# book4-boot: /usr/local/bin comes first in PATH and /etc/pacman.d/hooks
# overrides the packaged hooks of the same name, so these always go.
replace /usr/local/bin/book4-boot
replace /usr/local/share/book4/x1-el2-book4.dtso
replace /etc/pacman.d/hooks/91-book4-boot.hook
replace /etc/pacman.d/hooks/61-book4-boot-remove.hook
for r in 90-book4-fingerprint 90-book4-usb-nowake 91-book4-boost 99-book4-keyboard; do
    retire "/etc/udev/rules.d/$r.rules" "/usr/lib/udev/rules.d/$r.rules"
done
for m in book4-no-battmgr book4-no-pwrlmts book4-spss-nvm; do
    retire "/etc/modprobe.d/$m.conf" "/usr/lib/modprobe.d/$m.conf"
done
retire /etc/modules-load.d/book4-cpufreq.conf         /usr/lib/modules-load.d/book4-cpufreq.conf
retire /etc/systemd/journald.conf.d/60-book4-sync.conf /usr/lib/systemd/journald.conf.d/60-book4-sync.conf
# user level
userunits=(book4-battery-warn.timer book4-gpu-busy.service)
systemctl --user disable -q "${userunits[@]}" 2>/dev/null || true
for u in book4-battery-warn.service book4-battery-warn.timer book4-gpu-busy.service; do
    retire "$HOME/.config/systemd/user/$u" "/usr/lib/systemd/user/$u" user
done
retire "$HOME/.local/bin/book4-battery-warn" /usr/lib/book4/book4-battery-warn user
retire "$HOME/.local/bin/book4-gpu-busy"     /usr/lib/book4/book4-gpu-busy user
retire "$HOME/.config/pipewire/pipewire.conf.d/book4-speakers.conf" /usr/share/pipewire/pipewire.conf.d/book4-speakers.conf user
retire "$HOME/.config/pipewire/pipewire.conf.d/book4-mic-ns.conf"   /usr/share/pipewire/pipewire.conf.d/book4-mic-ns.conf user
retire "$HOME/.config/pipewire/pipewire.conf.d/book4-clock.conf"    /usr/share/pipewire/pipewire.conf.d/book4-clock.conf user
retire "$HOME/.config/wireplumber/wireplumber.conf.d/book4-speakers.conf" /usr/share/wireplumber/wireplumber.conf.d/book4-speakers.conf user
retire "$HOME/.config/wireplumber/wireplumber.conf.d/90-book4-software-volume.conf" \
       /usr/share/wireplumber/wireplumber.conf.d/90-book4-software-volume.conf user
sudo rmdir /usr/local/lib/book4 /usr/local/share/book4 2>/dev/null || true

echo "== 4. units from /usr/lib"
sudo systemctl daemon-reload; sudo udevadm control --reload
sudo systemctl enable -q "${sysunits[@]/%/.service}"
systemctl --user daemon-reload
systemctl --user enable -q --now "${userunits[@]}"
for u in "${sysunits[@]}"; do printf '   %-28s %s  %s\n' "$u" "$(systemctl is-enabled "$u" 2>&1)" "$(systemctl show -P FragmentPath "$u")"; done
for u in "${userunits[@]}"; do printf '   %-28s %s  %s\n' "$u" "$(systemctl --user is-enabled "$u" 2>&1)" "$(systemctl --user show -P FragmentPath "$u")"; done
echo
echo "Backups of every removed copy: $bk"
[ ${#kept[@]} -eq 0 ] || { echo "Kept (differ from the package; look at them):"; printf '   %s\n' "${kept[@]}"; }
echo "Reboot when convenient (the initramfs was rebuilt by book4-boot's hook)."
