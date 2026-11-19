#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Install book4-boot and its pacman hooks (userspace/boot/arch, plan part B3)
# and write the first Arch GRUB menu with it. From then on, installing,
# upgrading or removing a linux-book4* package keeps /boot (sda4) and
# /grub/grub.cfg current, and so does an update of firmware, systemd or
# mkinitcpio hooks (the initramfs is rebuilt). Run as your user on Arch:
#
#   bash install/arch/book4-boot-setup.sh          install (again) and write the menu
#   bash install/arch/book4-boot-setup.sh undo     remove the script, hooks and settings
#
# Settings: /etc/book4/boot.conf, written once from the running command line;
# edit it and run 'sudo book4-boot menu'.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); repo=$(cd "$here/../.." && pwd)
src=$repo/userspace/boot/arch
conf=/etc/book4/boot.conf
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }

if [ "${1:-}" = undo ]; then
    sudo rm -f /usr/local/bin/book4-boot /etc/pacman.d/hooks/91-book4-boot.hook \
        /etc/pacman.d/hooks/61-book4-boot-remove.hook /usr/local/share/book4/x1-el2-book4.dtso "$conf"
    echo "book4-boot removed (/boot and /grub/grub.cfg left as they are)"; exit 0
fi

for c in dtc fdtoverlay fdtget mkinitcpio grub-script-check; do
    command -v $c >/dev/null || { echo "error: $c missing (dtc, mkinitcpio, grub)" >&2; exit 1; }
done
bash -n "$src/book4-boot"
sudo -v
if pacman -Q book4-edge-boot >/dev/null 2>&1; then
    echo "== 1. book4-boot and its hooks: from the book4-edge-boot package"
else
    echo "== 1. book4-boot, overlay, pacman hooks (better: the book4-edge-boot package)"
    sudo install -D -m 755 "$src/book4-boot" /usr/local/bin/book4-boot
    sudo install -D -m 644 "$repo/dts/src/x1-el2-book4.dtso" /usr/local/share/book4/x1-el2-book4.dtso
    sudo install -D -m 644 "$src/91-book4-boot.hook" /etc/pacman.d/hooks/91-book4-boot.hook
    sudo install -D -m 644 "$src/61-book4-boot-remove.hook" /etc/pacman.d/hooks/61-book4-boot-remove.hook
fi

echo "== 2. $conf"
if sudo test -e "$conf"; then
    echo "   kept (exists)"
else
    # The running arguments without the per-entry ones (root, subvolume, EL2, GRUB's).
    args=$(tr ' ' '\n' < /proc/cmdline | grep -vE '^(BOOT_IMAGE=|root=|rootflags=|id_aa64mmfr0\.ecv=|initrd=|$)' | paste -sd' ')
    [[ " $args " == *" ro "* ]] || args="ro $args"
    sudo tee "$conf" >/dev/null <<EOF
# book4-boot (book4-edge-linux userspace/boot/arch). After editing:
#   sudo book4-boot menu
# Kernel arguments of every entry; book4-boot adds root=, rootflags=subvol=
# (the running subvolume) and, at EL2, id_aa64mmfr0.ecv=1.
CMDLINE="$args"
# Menu titles: "\$NAME (<kernel release>)"
NAME="Omarchy"
# The package whose kernel is the default entry
DEFAULT_PKG=linux-book4
# Kernels from before book4-boot (no /dtb-<release>/ of their own):
# "<release>=<EL2 DTB under /boot>"; listed while their files exist.
LEGACY_DTB=("7.2.7-book4s=/dtb-test/book4-sleep-el2.dtb")
EOF
    echo "   CMDLINE=\"$args\""
fi

echo "== 3. /boot for $(pacman -Q linux-book4) and the menu"
rel=$(pacman -Ql linux-book4 | awk -F/ '$4=="modules" && $5!="" {print $5; exit}')
sudo book4-boot kernel "$rel"
sudo book4-boot menu --print | grep -E '^menuentry|^    (linux|devicetree)' | sed 's/^/   /'
echo
echo "Done. Arch GRUB's menu is written; your normal boot (Fedora's GRUB) is unchanged."
echo "Try it: bash install/arch/arch-grub.sh next, then reboot."
