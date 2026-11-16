#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Fingers enrolled in Windows Hello also unlock Linux
# (userspace/fingerprint/book4-fingerprint-import, from Rafael Meneses'
# SB4-Edge-Linux). The sensor keeps the prints on the chip; Windows and
# Linux each delete on-chip prints they do not know, so:
#   1. In Linux, delete the fingers enrolled here:  fprintd-delete $USER
#   2. In Windows: Settings > Accounts > Sign-in options > Fingerprint, enroll.
#   3. Back in Linux the service picks the new prints up at every boot, or
#      at once with:  sudo book4-fingerprint-import        (--list to look)
# Never enroll the same finger in both systems.
# Needs the SDCP libfprint already installed (install/arch/sync-fingerprint.sh).
#
#   bash install/arch/fingerprint-import.sh [undo]
set -euo pipefail
src=$(cd "$(dirname "$0")/../../userspace/fingerprint" && pwd)
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
sudo -v
if [ "${1:-}" = undo ]; then
    sudo systemctl disable book4-fingerprint-import.service 2>/dev/null || true
    sudo rm -f /usr/local/sbin/book4-fingerprint-import /etc/systemd/system/book4-fingerprint-import.service
    sudo systemctl daemon-reload
    echo "Removed (prints already imported stay in /var/lib/fprint)."
    exit 0
fi
python3 -c "import gi; gi.require_version('FPrint','2.0'); from gi.repository import FPrint" ||
    { echo "error: python-gobject or libfprint's introspection data is missing" >&2; exit 1; }
sudo install -D -m 755 "$src/book4-fingerprint-import" /usr/local/sbin/book4-fingerprint-import
sudo install -m 644 "$src/book4-fingerprint-import.service" /etc/systemd/system/book4-fingerprint-import.service
sudo systemctl daemon-reload
sudo systemctl enable book4-fingerprint-import.service
echo "Installed. What the sensor holds now:"
sudo /usr/local/sbin/book4-fingerprint-import --list || true
