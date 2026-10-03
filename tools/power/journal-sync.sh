#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Debug: journald writes to disk every second, and resume prints PM debug
# messages, so the last seconds before a reset reach the disk.
# Undo: bash ~/journal-sync.sh undo
set -eu
sudo -v
if [ "${1:-}" = undo ]; then
    sudo rm -f /etc/systemd/journald.conf.d/book4-debug.conf
else
    sudo install -D -m 644 /dev/stdin /etc/systemd/journald.conf.d/book4-debug.conf <<'EOF'
[Journal]
SyncIntervalSec=1s
EOF
    echo 1 | sudo tee /sys/power/pm_debug_messages >/dev/null
fi
sudo systemctl restart systemd-journald
echo "journald: $(systemd-analyze cat-config systemd/journald.conf | grep -i SyncInterval || echo default)"
