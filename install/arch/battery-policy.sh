#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Low battery: a last warning at 5 % and a clean power-off at 3 %.
# Omarchy's shell warns once at 10 %; UPower's critical action was "Auto",
# which picks hybrid sleep/hibernation because the swap file exists, and that
# cannot work at EL2 (no EFI variables, no HibernateLocation): on 20 October
# the machine tried to sleep at the last percent and died.
#   /etc/UPower/UPower.conf.d/70-book4.conf   PowerOff at 3 %
#   ~/.local/bin/book4-battery-warn + user timer book4-battery-warn.timer
#        (every minute; one critical notification per discharge at <= 5 %)
# Run on Arch as your user:  bash install/arch/battery-policy.sh [undo]
set -euo pipefail
src=$(cd "$(dirname "$0")/../../userspace/battery" && pwd)
conf=/etc/UPower/UPower.conf.d/70-book4.conf
bin=$HOME/.local/bin/book4-battery-warn
units=$HOME/.config/systemd/user

[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
sudo -v

if [ "${1:-}" = undo ]; then
    systemctl --user disable --now book4-battery-warn.timer 2>/dev/null || true
    rm -f "$bin" "$units/book4-battery-warn.service" "$units/book4-battery-warn.timer"
    systemctl --user daemon-reload
    sudo rm -f "$conf"; sudo systemctl restart upower
    echo "Removed: back to UPower's defaults and Omarchy's single warning."
    exit 0
fi

sudo install -D -m 644 "$src/70-book4.conf" "$conf"
sudo systemctl restart upower
install -D -m 755 "$src/book4-battery-warn" "$bin"
install -D -m 644 -t "$units" "$src/book4-battery-warn.service" "$src/book4-battery-warn.timer"
systemctl --user daemon-reload
systemctl --user enable --now book4-battery-warn.timer
echo "UPower: $(grep -h CriticalPowerAction "$conf"), action at $(grep -h PercentageAction "$conf" | cut -d= -f2) %"
systemctl --user list-timers book4-battery-warn.timer --no-pager | head -2
