#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Add the experimental camera device tree as an extra GRUB entry
# ("alt DT camera.dtb") for the default (Anatase) kernel. The normal entries
# are untouched. Undo: bash camera-dtb.sh remove. Run as your user.
set -eu
HOOK=/etc/kernel/install.d/99-book4-devicetree.install
SRC=~/src/patchwork/arch/arm64/boot/dts/qcom/x1e80100-samsung-galaxy-book4-edge-14-camera.dtb
K=$(cat /etc/book4/default-kernel)
sudo -v
if [ "${1:-}" = remove ]; then
    sudo rm -f /etc/book4/test-dtb
else
    sudo install -d -m 755 /boot/dtb-test
    sudo dtc -q -I dtb -O dtb -p 8192 -o /boot/dtb-test/camera.dtb "$SRC"
    echo /dtb-test/camera.dtb | sudo tee /etc/book4/test-dtb >/dev/null
fi
sudo "$HOOK" add "$K"
sudo grep -E '^menuentry|cutmem' /boot/efi/EFI/fedora/grub.cfg
