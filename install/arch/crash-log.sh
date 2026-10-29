#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Logs that survive a hard reset (no panic, no pstore: see docs/TODO.md).
#   /etc/systemd/journald.conf.d/60-book4-sync.conf   journald syncs every
#        10 s instead of 5 min
#   /usr/local/bin/book4-live-log + book4-live-log.service   plain-text copy
#        of each boot's journal in /var/log/book4-live/<boot id>.log, synced
#        every 2 s; journald can discard a whole damaged file after a reset
#        (29 October: 22 h lost), an appended text file cannot
# After a reset:  ls -t /var/log/book4-live | sed -n 2p   (the previous boot)
# For the very last second use a second machine too (netconsole or
# `ssh book4 dmesg -w`): nothing local is guaranteed past the last sync.
# Run on Arch as your user:  bash install/arch/crash-log.sh [undo]
set -euo pipefail
src=$(cd "$(dirname "$0")/../../userspace/crash-log" && pwd)
conf=/etc/systemd/journald.conf.d/60-book4-sync.conf
bin=/usr/local/bin/book4-live-log
unit=/etc/systemd/system/book4-live-log.service

[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
sudo -v

if [ "${1:-}" = undo ]; then
    sudo systemctl disable --now book4-live-log.service 2>/dev/null || true
    sudo rm -f "$conf" "$bin" "$unit"
    sudo systemctl daemon-reload
    sudo systemctl restart systemd-journald
    echo "Removed (/var/log/book4-live kept)."
    exit 0
fi

sudo install -D -m 644 "$src/60-book4-sync.conf" "$conf"
sudo systemctl restart systemd-journald
sudo install -D -m 755 "$src/book4-live-log" "$bin"
sudo install -m 644 "$src/book4-live-log.service" "$unit"
sudo systemctl daemon-reload
sudo systemctl enable --now book4-live-log.service
sleep 3
echo "journald: $(systemd-analyze cat-config systemd/journald.conf | grep -i '^SyncInterval')"
systemctl is-active book4-live-log.service
ls -la /var/log/book4-live/
