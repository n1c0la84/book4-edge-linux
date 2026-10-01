#!/bin/bash
# Install the current boot hook from this repo and regenerate grub.cfg.
#   bash install/update-boot-hook.sh
set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)
HOOK=/etc/kernel/install.d/99-book4-devicetree.install
sudo -v
sudo install -m 755 "$REPO/userspace/boot/99-book4-devicetree.install" "$HOOK"
sudo "$HOOK" add "$(uname -r)"
sudo grep -E '^menuentry' /boot/efi/EFI/fedora/grub.cfg
