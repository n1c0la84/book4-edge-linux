#!/bin/bash
# Protect the static ESP grub.cfg from GRUB package updates (see docs/updates.md),
# then prove it works on the pending GRUB upgrade.
#   bash install/guard-grub.sh
set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)
CFG=/boot/efi/EFI/fedora/grub.cfg
sudo -v
sudo dnf install -y libdnf5-plugin-actions
sudo install -m 755 "$REPO/userspace/dnf/book4-regen-grub" /usr/local/sbin/book4-regen-grub
sudo install -D -m 644 "$REPO/userspace/dnf/book4-grub.actions" /etc/dnf/libdnf5-plugins/actions.d/book4-grub.actions
echo "== test: upgrade only the GRUB packages (their script overwrites grub.cfg; our action must restore it)"
sudo dnf upgrade -y 'grub2*'
echo "== result"
if sudo grep -q cutmem $CFG && sudo grep -q devicetree $CFG; then
    echo "OK: grub.cfg still has cutmem and devicetree"
    sudo grep -E '^menuentry' $CFG
else
    echo "NOT OK - restoring by hand now"
    sudo /etc/kernel/install.d/99-book4-devicetree.install add "$(uname -r)"
    sudo grep -c cutmem $CFG
fi
