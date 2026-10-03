#!/bin/bash
# Install a kernel built from the Anatase tree (see docs/kernel.md) next to the
# Fedora kernel. The Fedora kernel stays the pinned default; the new one appears
# in the GRUB menu as "(other)" until it has been tested and pinned.
#
#   bash install/install-anatase-kernel.sh [TREE]     (default TREE: ~/src/patchwork)
#
# Build first, as your user:  make -j$(nproc) LOCALVERSION= all
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
TREE=${1:-$HOME/src/patchwork}
OUT=$HOME/book4-kernel-install.txt
exec > >(tee "$OUT") 2>&1
cd "$TREE"
KREL=$(make -s LOCALVERSION= kernelrelease)
DTB=x1e80100-samsung-galaxy-book4-edge-14.dtb
echo "== installing $KREL from $TREE"
[ -e arch/arm64/boot/dts/qcom/$DTB ] || { echo "no $DTB built - run the build first"; exit 1; }
[ -e arch/arm64/boot/vmlinuz.efi ] || [ -e arch/arm64/boot/Image ] || { echo "no kernel image built"; exit 1; }
sudo -v

step() { printf '\n== %s\n' "$*"; }

step "DKMS: build our out-of-tree drivers for Fedora kernels only"
# The Anatase kernel has these drivers built in; a DKMS copy in extra/ would
# shadow them (extra/ wins over kernel/ in depmod's search order).
for d in /usr/src/book4-edge-anatase-* /usr/src/book4-ec-* /usr/src/book4-kbd-backlight-*; do
    [ -e "$d/dkms.conf" ] || continue
    sudo sed -i '/^BUILD_EXCLUSIVE_KERNEL=/d' "$d/dkms.conf"
    echo 'BUILD_EXCLUSIVE_KERNEL="^.*\.fc[0-9]+\..*$"' | sudo tee -a "$d/dkms.conf" >/dev/null
    echo "  $(basename "$d"): Fedora kernels only"
done

step "keyboard backlight: our experimental driver off (the Anatase EC driver does it)"
sudo systemctl disable --now book4-kbd-backlight.service 2>/dev/null || true

step "boot hook: use the DTB shipped with each kernel when there is one"
sudo install -m 755 "$REPO/userspace/boot/99-book4-devicetree.install" /etc/kernel/install.d/99-book4-devicetree.install

step "modules and device trees -> /usr/lib/modules/$KREL"
sudo make -s LOCALVERSION= modules_install
sudo make -s LOCALVERSION= dtbs_install INSTALL_DTBS_PATH=/usr/lib/modules/$KREL/dtb
ls -l /usr/lib/modules/$KREL/dtb/qcom/$DTB

step "kernel image + initramfs + boot entry (kernel-install runs dracut and our hook)"
sudo make -s LOCALVERSION= install

step "checks"
ls -l /boot/vmlinuz-$KREL /boot/initramfs-$KREL.img /boot/dtb-$KREL/$DTB
dkms status
sudo grep -c cutmem /boot/efi/EFI/fedora/grub.cfg
sudo grep -E '^menuentry' /boot/efi/EFI/fedora/grub.cfg
echo "default (pinned): $(cat /etc/book4/default-kernel)"
echo "== done. Reboot and pick \"Fedora Linux ($KREL) - Book4 Edge (other)\". Output: $OUT"
if [ -e /etc/book4/second-os ]; then
    echo "Arch: bash $REPO/install/arch/sync-kernel.sh $KREL  (again after pinning $KREL)"
fi
