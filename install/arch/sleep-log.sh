#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Measure every sleep in normal use (userspace/standby/book4-sleep-log):
# journalctl -t book4-sleep, or /var/log/book4-sleep.csv for the history.
# Run on Arch as your user:  bash install/arch/sleep-log.sh [undo]
set -euo pipefail
src=$(cd "$(dirname "$0")/../../userspace/standby" && pwd)/book4-sleep-log
hook=/usr/lib/systemd/system-sleep/book4-sleep-log
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
sudo -v
if [ "${1:-}" = undo ]; then
    sudo rm -f "$hook"
    echo "Removed $hook (/var/log/book4-sleep.csv kept)."
    exit 0
fi
sudo install -m 755 "$src" "$hook"
echo "Installed $hook. After the next sleep (and a minute awake):"
echo "  journalctl -t book4-sleep -n 5"
echo "  column -s, -t /var/log/book4-sleep.csv | tail"
