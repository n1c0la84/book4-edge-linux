#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Arch Linux ARM in a btrfs subvolume ("arch") next to Fedora, booting the
# same Anatase kernel and DTB. Stage 1: a bootable console system with
# NetworkManager, your user and sudo. Run as your user on Fedora (asks for
# passwords). Adjust the variables below first.
set -euo pipefail
K=7.2.7-book4
TAR=~/src/arch/ArchLinuxARM-aarch64-latest.tar.gz
REPO=$(cd "$(dirname "$0")/../.." && pwd)
U=${ARCH_USER:-$USER}           # user created in Arch
TZONE=${ARCH_TZ:-Europe/Rome}
TOP=/mnt/btrfs-top
R=$TOP/arch
DEV=/dev/sda5
ns() { sudo systemd-nspawn -q -D "$R" --resolv-conf=replace-uplink "$@"; }

sudo -v
echo "== 1. subvolume"
sudo mkdir -p $TOP
mountpoint -q $TOP || sudo mount -o subvolid=5 $DEV $TOP
if [ -e "$R/etc/mkinitcpio.conf.d/book4.conf" ]; then
    echo "   $R already unpacked and configured: resuming at step 5"
    RESUME=1
elif [ -e "$R" ]; then
    echo "$R exists but is incomplete: delete it with"
    echo "  sudo btrfs subvolume delete $R"
    exit 1
else
    RESUME=0
    sudo btrfs subvolume create "$R"
fi
if [ "$RESUME" = 0 ]; then

echo "== 2. Arch Linux ARM base system"
sudo tar -xpzf "$TAR" -C "$R" --numeric-owner --xattrs --xattrs-include='*' --acls

echo "== 3. kernel modules and our firmware"
sudo cp -a /usr/lib/modules/$K "$R/usr/lib/modules/"
# Our own firmware (DSP, GPU SQE, Wi-Fi c5, topology alias) under updates/,
# which the kernel searches first and pacman never touches.
FWU="$R/usr/lib/firmware/updates"
for f in qcom/x1e80100/SAMSUNG/galaxy-book4-edge qcom/gen70500_sqe.fw \
         ath12k/WCN7850/hw2.0/amss.bin ath12k/WCN7850/hw2.0/m3.bin \
         ath12k/WCN7850/hw2.0/board.bin ath12k/WCN7850/hw2.0/board-2.bin; do
    sudo install -d "$FWU/$(dirname $f)"
    sudo cp -aL "/usr/lib/firmware/$f" "$FWU/$f"
done
sudo install -d "$FWU/qcom/x1e80100"
sudo cp -L /usr/lib/firmware/updates/qcom/x1e80100/X1E80100-GalaxyBook4Edge-tplg.bin.xz "$FWU/qcom/x1e80100/"

echo "== 4. basic configuration"
UUID=$(sudo blkid -s UUID -o value $DEV)
echo "UUID=$UUID / btrfs rw,relatime,compress=zstd:1,subvol=/arch 0 0" | sudo tee "$R/etc/fstab" >/dev/null
echo book4-arch | sudo tee "$R/etc/hostname" >/dev/null
sudo ln -sf /usr/share/zoneinfo/$TZONE "$R/etc/localtime"
sudo sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' "$R/etc/locale.gen"
echo LANG=en_US.UTF-8 | sudo tee "$R/etc/locale.conf" >/dev/null
sudo install -D -m 644 $REPO/userspace/keyboard/99-book4-keyboard.rules "$R/etc/udev/rules.d/99-book4-keyboard.rules"
sudo install -D -m 644 $REPO/userspace/modprobe/book4-no-battmgr.conf "$R/etc/modprobe.d/book4-no-battmgr.conf"
sudo install -D -m 644 $REPO/userspace/modules-load/book4-cpufreq.conf "$R/etc/modules-load.d/book4-cpufreq.conf"
sudo install -D -m 644 /dev/stdin "$R/etc/mkinitcpio.conf.d/book4.conf" <<'EOF'
# Galaxy Book4 Edge: UFS is modular in the Anatase kernel; no autodetect
# (the image is built in a container on Fedora).
MODULES=(ufs_qcom ufshcd_pltfrm phy_qcom_qmp_ufs)
HOOKS=(base systemd modconf block filesystems keyboard fsck)
EOF

fi  # RESUME

echo "== 5. keys, update, packages (inside the new system)"
ns /bin/bash -euc "
[ -e /etc/pacman.d/gnupg/pubring.gpg ] || pacman-key --init
pacman-key --populate archlinuxarm
# The geo-redirecting default mirror stalled; fast ones measured from here first
printf 'Server = http://%s.mirror.archlinuxarm.org/\$arch/\$repo\n' dk de4 > /etc/pacman.d/mirrorlist.book4
grep -v '^#' /etc/pacman.d/mirrorlist | grep Server >> /etc/pacman.d/mirrorlist.book4
mv /etc/pacman.d/mirrorlist.book4 /etc/pacman.d/mirrorlist
cat /etc/pacman.d/mirrorlist
# Arch's own kernel is not used (the Anatase kernel is shared with Fedora)
pacman -Q linux-aarch64 >/dev/null 2>&1 && pacman -Rdd --noconfirm linux-aarch64
pacman -Syu --noconfirm
pacman -S --noconfirm --needed mkinitcpio networkmanager sudo btrfs-progs bluez bluez-utils nano vim linux-firmware linux-firmware-qcom alsa-ucm-conf
# mkinitcpio came in as a dependency of linux-aarch64; without that package it
# is an orphan, and orphan cleanup (pacman -Qtdq, omarchy update) would remove it
pacman -D --asexplicit mkinitcpio
# Fedora's tar dropped file capabilities (security.capability xattrs) when
# unpacking; reinstalling every package restores them.
pacman -S --noconfirm \$(pacman -Qqn)
locale-gen
depmod $K
systemctl enable NetworkManager bluetooth
systemctl disable systemd-networkd 2>/dev/null || true
userdel -r alarm 2>/dev/null || true
id $U >/dev/null 2>&1 || useradd -m -G wheel -s /bin/bash $U
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
passwd -l root
mkinitcpio -k $K -g /boot/initramfs-$K-book4.img
"
echo "== 6. password for your Arch user $U"
ns passwd $U

echo "== 7. GRUB entry"
sudo install -m 644 "$R/boot/initramfs-$K-book4.img" "/boot/initramfs-$K-arch.img"
echo "arch Arch Linux" | sudo tee /etc/book4/second-os >/dev/null
sudo install -m 755 $REPO/userspace/boot/99-book4-devicetree.install /etc/kernel/install.d/99-book4-devicetree.install
sudo /etc/kernel/install.d/99-book4-devicetree.install add "$K"
sudo grep -E '^menuentry' /boot/efi/EFI/fedora/grub.cfg
sudo umount $TOP
echo "Done. Reboot and pick 'Arch Linux ($K)'."
