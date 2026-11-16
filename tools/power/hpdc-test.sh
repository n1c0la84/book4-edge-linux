#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Board power in sleep (docs/TODO.md, ~0.7 W against Windows' 0.11 W): the
# one step of Windows' Modern Standby sequence never tried here. At
# "MS:LPS+" the firmware's PEP0._DSM sets \_SB.GIO0.HPDC = 1, TLMM GPIO 49
# (region POWS, next to MODS = GPIO 44, which made no difference on its
# own on 22 October). Linux leaves GPIO 49 as the firmware left it: output,
# low. What it switches is not known.
#
# This installs a systemd-sleep hook that drives GPIO 49 high before every
# sleep and low again after it; sleeps are then logged as "<entry>+hpdc".
# Compare a night on battery with one without (0.70 W on el2-sleep).
#
#   bash tools/power/hpdc-test.sh          install the hook
#   bash tools/power/hpdc-test.sh undo     remove it
set -euo pipefail
hook=/usr/lib/systemd/system-sleep/book4-hpdc
sudo -v
if [ "${1:-}" = undo ]; then sudo rm -f $hook; echo "removed $hook"; exit 0; fi
command -v gpioset >/dev/null || { echo "error: gpioset (libgpiod) missing" >&2; exit 1; }
sudo tee $hook >/dev/null <<'HOOK'
#!/bin/sh
# Book4 (tools/power/hpdc-test.sh): TLMM GPIO 49 (HPDC) high while asleep, as Windows sets it at MS:LPS+.
CHIP=$(for c in /sys/bus/gpio/devices/gpiochip*; do
         [ -e "$c" ] && readlink -f "$c" | grep -q f100000.pinctrl && basename "$c"; done | head -1)
[ -n "$CHIP" ] || exit 0
case "$1" in pre) v=1 ;; post) v=0 ;; *) exit 0 ;; esac
timeout 1 gpioset -c "$CHIP" 49=$v 2>/dev/null; rc=$?
[ $rc = 124 ] && logger -t book4-hpdc "GPIO 49 = $v ($1 $2)" || logger -t book4-hpdc "GPIO 49 not settable, rc=$rc"
exit 0
HOOK
sudo chmod 755 $hook
echo "Installed $hook. After a sleep: journalctl -t book4-hpdc -t book4-sleep -n 6"
