#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Make Arch the default GRUB entry, then apply the safe suspend defaults.
#  1. Fedora (container): install the current boot hook from the Arch repo
#     clone, write /etc/book4/default-os = second, regenerate grub.cfg.
#  2. install/arch/power-defaults.sh: pcie_port_pm=force + no USB wakeup
#     (regenerates grub.cfg again, now with Arch as default).
# Undo: delete /etc/book4/default-os in Fedora and rerun the hook;
#       bash ~/Projects/book4-edge-linux/install/arch/power-defaults.sh undo
# Run as yourself on Arch: bash install/arch/boot-defaults.sh
set -euo pipefail
repo=$HOME/Projects/book4-edge-linux
hook=$(base64 -w0 "$repo/userspace/boot/99-book4-devicetree.install")
bash "$repo/install/arch/mount-ro.sh" off >/dev/null 2>&1 || true
inner="set -euo pipefail
H=/etc/kernel/install.d/99-book4-devicetree.install
sudo cp -p \$H \$H.prev-defaultos
echo $hook | base64 -d | sudo tee \$H >/dev/null; sudo chmod 755 \$H
echo second | sudo tee /etc/book4/default-os >/dev/null
sudo \$H add \"\$(cat /etc/book4/default-kernel)\"
sudo grep -E '^set default|^menuentry' /boot/efi/EFI/fedora/grub.cfg"
bash "$repo/install/arch/fedora-shell.sh" bash -lc "$inner"
bash "$repo/install/arch/power-defaults.sh"
