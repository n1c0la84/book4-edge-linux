#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copilot key -> Super, through keyd (only for the internal keyboard 0cf2:9050).
#   /etc/keyd/book4.conf   from userspace/keyboard/keyd-book4.conf
# Run on Arch as your user:  bash install/arch/copilot-key.sh [undo]
# If the key does nothing afterwards, check what it sends: sudo keyd monitor
set -euo pipefail
src=$(cd "$(dirname "$0")/../../userspace/keyboard" && pwd)/keyd-book4.conf
conf=/etc/keyd/book4.conf

[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
sudo -v

if [ "${1:-}" = undo ]; then
    sudo rm -f "$conf"
    if [ -z "$(ls -A /etc/keyd 2>/dev/null)" ]; then
        sudo systemctl disable --now keyd
    else
        sudo keyd reload
    fi
    echo "Removed: the Copilot key sends Shift+Super+F23 again."
    exit 0
fi

sudo pacman -S --needed --noconfirm keyd
sudo install -D -m 644 "$src" "$conf"
sudo systemctl enable --now keyd
sudo keyd reload
systemctl is-active keyd
echo "Done: hold Copilot + Space, Copilot + Return, ... like Super."
