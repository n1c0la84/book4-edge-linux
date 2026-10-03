#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Give the Arch subvolume a kernel that is installed on Fedora: copy its
# modules into Arch, build Arch's initramfs for it (in a container, with
# Arch's own mkinitcpio and firmware), put it in /boot as
# initramfs-<kver>-arch.img and regenerate GRUB through our boot hook.
# The "Arch Linux" GRUB entry always uses Fedora's default kernel, and the hook
# only writes it when that kernel's -arch initramfs exists, so run this after
# installing a new kernel (install-anatase-kernel.sh) and again after pinning
# it as the default. Run as your user on Fedora, with Arch not running.
#
#   bash install/arch/sync-kernel.sh [KVER]     (default: /etc/book4/default-kernel)
#
# The previous Arch initramfs for KVER is kept as /boot/initramfs-KVER-arch.img.prev.
set -euo pipefail
K=${1:-$(cat /etc/book4/default-kernel)}
TOP=/mnt/btrfs-top
R=$TOP/arch
DEV=/dev/sda5
SUBVOL=arch
IMG=/boot/initramfs-$K-$SUBVOL.img
HOOK=/etc/kernel/install.d/99-book4-devicetree.install
ns() { sudo systemd-nspawn -q -D "$R" "$@"; }

[ -e /etc/fedora-release ] || { echo "Run this on Fedora (it reads Fedora's kernel and /boot)." >&2; exit 1; }
[ -d /usr/lib/modules/$K/kernel ] || { echo "No modules for $K in /usr/lib/modules." >&2; exit 1; }
[ -e /boot/vmlinuz-$K ] || { echo "No /boot/vmlinuz-$K: install the kernel first." >&2; exit 1; }

sudo -v
echo "== 1. Arch subvolume"
sudo mkdir -p $TOP
mounted_here=0
if ! mountpoint -q $TOP; then
    sudo mount -o subvolid=5 $DEV $TOP
    mounted_here=1
fi
cleanup() { [ $mounted_here = 1 ] && sudo umount $TOP || true; }
trap cleanup EXIT
[ -e "$R/etc/mkinitcpio.conf.d/book4.conf" ] || { echo "$R does not look like our Arch install." >&2; exit 1; }
ns pacman -Q mkinitcpio >/dev/null || { echo "mkinitcpio missing in Arch: pacman -S mkinitcpio there first." >&2; exit 1; }

echo "== 2. modules $K -> Arch"
# Replace, so modules removed from a rebuilt kernel do not linger.
sudo rm -rf "$R/usr/lib/modules/$K.new"
sudo cp -a /usr/lib/modules/$K "$R/usr/lib/modules/$K.new"
sudo rm -rf "$R/usr/lib/modules/$K"
sudo mv "$R/usr/lib/modules/$K.new" "$R/usr/lib/modules/$K"
ns depmod $K

echo "== 3. Arch initramfs"
ns mkinitcpio -k $K -g /boot/initramfs-$K-book4.img
# Without the UFS modules the root filesystem is never found.
# Capture the listing first: piping into grep -q closes the pipe early, the
# container is killed by SIGPIPE and pipefail reports a false failure.
LIST=$(ns lsinitcpio /boot/initramfs-$K-book4.img)
grep -qE '/ufs-qcom\.ko(\.[gx]z|\.zst)?$' <<<"$LIST" ||
    { echo "ufs-qcom.ko missing from the new initramfs, not installing it." >&2; exit 1; }
echo "   UFS driver present: $(grep -E '/ufs-qcom\.ko' <<<"$LIST")"

echo "== 4. $IMG"
[ -e "$IMG" ] && sudo cp -p "$IMG" "$IMG.prev"
sudo install -m 644 "$R/boot/initramfs-$K-book4.img" "$IMG.new"
sudo mv "$IMG.new" "$IMG"
ls -l "$IMG"*

echo "== 5. GRUB (our boot hook)"
sudo "$HOOK" add "$K"
sudo grep -c cutmem /boot/efi/EFI/fedora/grub.cfg
sudo grep -E '^menuentry' /boot/efi/EFI/fedora/grub.cfg
if [ "$K" != "$(cat /etc/book4/default-kernel)" ]; then
    echo "Note: $K is not the default kernel; the Arch entry keeps using $(cat /etc/book4/default-kernel) until $K is pinned."
fi

echo "== stale Arch kernels (no longer installed on Fedora; remove by hand if you like)"
for d in "$R"/usr/lib/modules/*/; do
    k=$(basename "$d")
    [ -d /usr/lib/modules/$k ] || echo "   $R/usr/lib/modules/$k"
done
for f in /boot/initramfs-*-$SUBVOL.img; do
    k=${f#/boot/initramfs-}; k=${k%-$SUBVOL.img}
    [ -e /boot/vmlinuz-$k ] || echo "   $f"
done
echo "Done."
