#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# When to hibernate (after hibernate-setup.sh and a successful manual test).
# The PMIC RTC has no wake alarm here (rtc-pm8xxx, no wakealarm), so
# suspend-then-hibernate cannot wake up to hibernate. Instead:
#   lid closed on battery  -> hibernate
#   lid closed on AC       -> suspend (as before)
#   critical battery (2 %) -> hibernate (UPower; only while awake)
# Drop-ins only; Omarchy's own logind drop-ins are left alone.
#
# Run as your user on Arch:  bash install/arch/hibernate-lid.sh [undo]
set -euo pipefail
undo=${1:-}
logind=/etc/systemd/logind.conf.d/90-book4-hibernate.conf
upower=/etc/UPower/UPower.conf.d/90-book4-hibernate.conf

[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
sudo -v
if [ "$undo" = undo ]; then
    sudo rm -f "$logind" "$upower"
else
    swapon --show=NAME --noheadings | grep -qx /swap/swapfile ||
        { echo "No /swap/swapfile active: run install/arch/hibernate-setup.sh first." >&2; exit 1; }
    sudo mkdir -p "$(dirname "$logind")" "$(dirname "$upower")"
    printf '%s\n' '# Book4 (install/arch/hibernate-lid.sh): s2idle drains the battery overnight' \
        '[Login]' 'HandleLidSwitch=hibernate' 'HandleLidSwitchExternalPower=suspend' |
        sudo tee "$logind" >/dev/null
    printf '%s\n' '# Book4 (install/arch/hibernate-lid.sh)' \
        '[UPower]' 'CriticalPowerAction=Hibernate' |
        sudo tee "$upower" >/dev/null
fi
# HUP makes logind re-read its configuration without ending the session.
sudo systemctl kill -s HUP systemd-logind
sudo systemctl try-restart upower
echo "logind lid: $(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager HandleLidSwitch 2>/dev/null || echo '?')," \
     "on AC: $(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager HandleLidSwitchExternalPower 2>/dev/null || echo '?')"
