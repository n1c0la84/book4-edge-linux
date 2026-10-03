#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Test: disable every wakeup source except the lid (gpio-keys) and the power
# key, until the next reboot, then unplug the charger during sleep.
# If it still crashes, nothing in Linux woke up for it. Run as your user.
set -u
sudo -v
n=0
for w in $(find /sys/devices -path '*/power/wakeup' 2>/dev/null); do
    [ "$(cat "$w" 2>/dev/null)" = enabled ] || continue
    d=${w%/power/wakeup}
    case "$d" in *gpio-keys*|*pwrkey*) echo "kept:     ${d#/sys/devices/}"; continue;; esac
    echo disabled | sudo tee "$w" >/dev/null && { echo "disabled: ${d#/sys/devices/}"; n=$((n+1)); }
done
echo "$n wakeup sources disabled until reboot."
echo "Now: charger in (Charging), lid closed 1 min, unplug, wait 2 min, then open the lid."
