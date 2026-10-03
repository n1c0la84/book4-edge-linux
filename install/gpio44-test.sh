#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Test: free GPIO 44 (MODS) and drive it like Windows around sleep.
# Adds a separate GRUB entry "alt DT gpio44.dtb" (default untouched) and a
# systemd-sleep hook that only acts when that DTB is booted.
# Undo: bash ~/gpio44-test.sh undo
set -euo pipefail
sudo -v
if [ "${1:-}" = undo ]; then
    sudo rm -f /usr/lib/systemd/system-sleep/book4-mods
    echo /dtb-test/camera.dtb | sudo tee /etc/book4/test-dtb >/dev/null
else
    sudo install -d -m 755 /boot/dtb-test
    sudo dtc -q -I dtb -O dtb -p 8192 -o /boot/dtb-test/gpio44.dtb ${GPIO44_DTB:-$HOME/src/gpio44/gpio44.dtb}
    echo /dtb-test/gpio44.dtb | sudo tee /etc/book4/test-dtb >/dev/null
    sudo install -m 755 "$(dirname "$0")/../userspace/standby/book4-mods" /usr/lib/systemd/system-sleep/book4-mods
fi
sudo /etc/kernel/install.d/99-book4-devicetree.install add "$(cat /etc/book4/default-kernel)"
sudo grep -E '^menuentry' /boot/efi/EFI/fedora/grub.cfg
