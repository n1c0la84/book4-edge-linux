#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Make SDDM start Omarchy's session through uwsm ("Hyprland (uwsm-managed)").
# SDDM reuses the last session chosen; on 8 Oct it was the plain "Hyprland"
# entry, and then Omarchy's logout (omarchy-system-logout: uwsm stop) did
# nothing ("Compositor is not running"). Sets [Last] Session in SDDM's
# state file; takes effect at the next login.
#
#   bash install/arch/sddm-uwsm-session.sh      (as your user on Arch)
set -euo pipefail
S=/var/lib/sddm/state.conf
D=/usr/share/wayland-sessions/hyprland-uwsm.desktop
[ -e "$D" ] || { echo "No $D (uwsm not installed?)." >&2; exit 1; }
sudo -v
sudo touch "$S"
sudo cp -p "$S" "$S.pre-uwsm"
if sudo grep -q '^\[Last\]' "$S"; then
    if sudo grep -q '^Session=' "$S"; then
        sudo sed -i "s|^Session=.*|Session=$D|" "$S"
    else
        sudo sed -i "/^\[Last\]/a Session=$D" "$S"
    fi
else
    printf '[Last]\nSession=%s\nUser=%s\n' "$D" "$USER" | sudo tee -a "$S" >/dev/null
fi
sudo chown sddm:sddm "$S" 2>/dev/null || true
echo "== $S"; sudo cat "$S"
