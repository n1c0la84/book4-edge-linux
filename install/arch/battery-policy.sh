#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Low battery: a last warning at 5 % and a clean power-off at 3 %.
# Omarchy's shell warns once at 10 %; UPower's critical action was "Auto",
# which picks hybrid sleep/hibernation because the swap file exists; that
# resume resets this machine, and on 20 October (EL2, before EFI variables
# worked there) the machine tried to sleep at the last percent and died.
#   /etc/UPower/UPower.conf.d/70-book4.conf   PowerOff at 3 %
#   ~/.local/bin/book4-battery-warn + user timer book4-battery-warn.timer
#        (every minute; one critical notification per discharge at <= 5 %)
#   /etc/udev/rules.d/91-book4-boost.rules   the 4.0 GHz CPU boost on the
#        charger only (needs sleep-backport 0037 for schedutil to use it)
# Run on Arch as your user:  bash install/arch/battery-policy.sh [undo]
set -euo pipefail
src=$(cd "$(dirname "$0")/../../userspace/battery" && pwd)
conf=/etc/UPower/UPower.conf.d/70-book4.conf
rule=/etc/udev/rules.d/91-book4-boost.rules
bin=$HOME/.local/bin/book4-battery-warn
units=$HOME/.config/systemd/user

[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
sudo -v

if [ "${1:-}" = undo ]; then
    systemctl --user disable --now book4-battery-warn.timer 2>/dev/null || true
    rm -f "$bin" "$units/book4-battery-warn.service" "$units/book4-battery-warn.timer"
    systemctl --user daemon-reload
    sudo rm -f "$conf" "$rule"; sudo systemctl restart upower; sudo udevadm control --reload
    echo "Removed: back to UPower's defaults, Omarchy's single warning, boost as the kernel sets it."
    exit 0
fi

sudo install -D -m 644 "$src/70-book4.conf" "$conf"
sudo systemctl restart upower
sudo install -m 644 "$src/91-book4-boost.rules" "$rule"
sudo udevadm control --reload
sudo udevadm trigger --action=change /sys/class/power_supply/samsung-galaxybook-ac
echo "CPU boost: $(cat /sys/devices/system/cpu/cpufreq/boost) (1 on the charger, 0 on battery)"
install -D -m 755 "$src/book4-battery-warn" "$bin"
install -D -m 644 -t "$units" "$src/book4-battery-warn.service" "$src/book4-battery-warn.timer"
systemctl --user daemon-reload
systemctl --user enable --now book4-battery-warn.timer
echo "UPower: $(grep -h CriticalPowerAction "$conf"), action at $(grep -h PercentageAction "$conf" | cut -d= -f2) %"
systemctl --user list-timers book4-battery-warn.timer --no-pager | head -2
