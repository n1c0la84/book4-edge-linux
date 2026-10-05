#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Experimental four-speaker DTB as a separate GRUB entry "alt DT speakers.dtb"
# for the default kernel; the normal entry is unchanged.
# Undo: bash ~/speakers-dtb.sh undo
set -euo pipefail
sudo -v
if [ "${1:-}" = undo ]; then
    echo /dtb-test/camera.dtb | sudo tee /etc/book4/test-dtb >/dev/null
else
    sudo install -d -m 755 /boot/dtb-test
    sudo dtc -q -I dtb -O dtb -p 8192 -o /boot/dtb-test/speakers.dtb ${SPEAKERS_DTB:-$HOME/src/speakers/speakers.dtb}
    echo /dtb-test/speakers.dtb | sudo tee /etc/book4/test-dtb >/dev/null
fi
sudo /etc/kernel/install.d/99-book4-devicetree.install add "$(cat /etc/book4/default-kernel)"
sudo grep -E '^menuentry' /boot/efi/EFI/fedora/grub.cfg
