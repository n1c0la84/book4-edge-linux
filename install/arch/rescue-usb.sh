#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build a bootable rescue USB stick for the Galaxy Book4 Edge 14": a minimal
# Arch Linux ARM (text console, Wi-Fi, btrfs/partition tools, this repo) with
# the Anatase kernel, our device tree and a GRUB that does the cutmem
# workaround, plus a btrfs partition for a backup (tools/backup/linux-backup.sh).
# A generic live USB cannot boot this machine: no cutmem (instant reset), no
# device tree, no Anatase drivers (black screen, no USB-C host).
#
#   bash install/arch/rescue-usb.sh /dev/sdX      (run as your user on Arch)
#   GRUB_ONLY=1 bash install/arch/rescue-usb.sh /dev/sdX
#        on a finished stick: rebuild only its GRUB (step 8)
#
# WIPES /dev/sdX. Refuses the internal disk, non-USB disks and mounted ones.
# Resumable: on a stick that already has the three BOOK4 partitions it offers
# to continue (reusing the filesystems, skipping the finished steps) instead
# of wiping. sudo is kept alive in the background for the whole run.
# Nothing is written to the internal disk, its ESP or the firmware's boot
# entries: GRUB is built with grub-mkstandalone inside the stick's own system
# and copied to the stick's EFI/BOOT/BOOTAA64.EFI (the removable-media path).
# Boot it from the firmware's boot menu.
#
# Layout: 1 BOOK4-ESP 512 MiB FAT32 (GRUB, kernel, initramfs, DTB),
#         2 BOOK4-RESCUE 8 GiB ext4 (the system), 3 BOOK4-BACKUP rest, btrfs.
set -euo pipefail
DEV=${1:?usage: $0 /dev/sdX   (the USB stick; it will be wiped)}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
U=$(id -un)
K=$(uname -r)
CACHE=$HOME/src/rescue
TARBALL=ArchLinuxARM-aarch64-latest.tar.gz
MIRROR=http://de4.mirror.archlinuxarm.org/os
DEV_BOOT=/dev/disk/by-uuid/3c3204e5-ed67-4e72-b0dc-75b7e3cdb3a5   # Fedora /boot (sda4)
DEV_ESP=/dev/disk/by-uuid/EE27-EF4A                               # internal ESP
M=$(mktemp -d)                                                    # mount points
R=$M/root
ns() { sudo systemd-nspawn -q -D "$R" --resolv-conf=replace-uplink "$@"; }

(( EUID != 0 )) || { echo "Run as your user, not as root." >&2; exit 1; }
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }

echo "== 0. target $DEV"
[ -b "$DEV" ] && [ "$(lsblk -dno TYPE "$DEV")" = disk ] || { echo "$DEV is not a whole disk." >&2; exit 1; }
root_disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE / | sed 's/\[.*//')")
[ "$(basename "$DEV")" != "$root_disk" ] || { echo "$DEV holds the running system." >&2; exit 1; }
[ "$(lsblk -dno TRAN "$DEV")" = usb ] || { echo "$DEV is not a USB disk." >&2; exit 1; }
if lsblk -no MOUNTPOINTS "$DEV" | grep -q .; then
    echo "$DEV has mounted partitions; unmount them first:" >&2; lsblk "$DEV" >&2; exit 1
fi
lsblk -o NAME,SIZE,MODEL,TRAN,LABEL "$DEV"
RESUME=0
if [ "$(lsblk -lno LABEL "$DEV" | tr '\n' ' ')" = " BOOK4ESP BOOK4-RESCUE BOOK4-BACKUP " ]; then
    read -r -p "$DEV already has the rescue partitions. Resume that build (no wipe)? Type YES: " ok
    [ "$ok" = YES ] || { echo "Aborted (to start over, wipe it first: sudo wipefs -a $DEV)."; exit 1; }
    RESUME=1
else
    read -r -p "Wipe $DEV ($(lsblk -dno SIZE "$DEV") $(lsblk -dno MODEL "$DEV")) and build the rescue stick? Type YES: " ok
    [ "$ok" = YES ] || { echo "Aborted."; exit 1; }
fi
sudo -v
# Keep sudo's timestamp fresh: long downloads and package updates outlast it,
# and an unanswered prompt mid-run is how the first build died.
( while sleep 50; do sudo -n -v 2>/dev/null || exit; done ) &
KEEPALIVE=$!
cleanup() {
    kill "$KEEPALIVE" 2>/dev/null || true
    sync
    for d in "$R/boot/efi" "$R" "$M/fboot" "$M/fesp"; do mountpoint -q "$d" && sudo umount "$d" || true; done
}
trap cleanup EXIT

GRUB_ONLY=${GRUB_ONLY:-0}
(( ! GRUB_ONLY || RESUME )) || { echo "GRUB_ONLY needs a stick that already has the rescue partitions." >&2; exit 1; }

if (( ! RESUME )); then
echo "== 1. Arch Linux ARM tarball (signature checked)"
mkdir -p "$CACHE"
curl -fL -o "$CACHE/$TARBALL" -z "$CACHE/$TARBALL" "$MIRROR/$TARBALL"
curl -fsL -o "$CACHE/$TARBALL.sig" "$MIRROR/$TARBALL.sig"
sudo pacman-key --verify "$CACHE/$TARBALL.sig" "$CACHE/$TARBALL"
fi

echo "== 2. kernel, device tree and command line of the running Arch"
mkdir -p "$M/fboot" "$M/fesp"
sudo mount -o ro "$DEV_BOOT" "$M/fboot"
sudo mount -o ro "$DEV_ESP" "$M/fesp"
DTB=$(sudo awk '/^menuentry "Arch Linux/{f=1} f && $1=="devicetree"{sub(/^\(\$bootdev\)/,"",$2); print $2; exit}' "$M/fesp/EFI/fedora/grub.cfg")
[ -n "$DTB" ] && [ -e "$M/fboot$DTB" ] || { echo "No Arch entry / DTB found in the internal grub.cfg." >&2; exit 1; }
[ -e "$M/fboot/vmlinuz-$K" ] || { echo "No /boot/vmlinuz-$K on Fedora's /boot." >&2; exit 1; }
# Same parameters as now, minus the root of the internal Arch.
CMDLINE=$(sed -E 's/^BOOT_IMAGE=[^ ]+ //; s/(^| )root=[^ ]+//; s/(^| )rootflags=[^ ]+//; s/(^| )ro( |$)/ /' /proc/cmdline | tr -s ' ')
echo "   kernel $K, DTB $DTB"
echo "   cmdline:$CMDLINE"

mapfile -t P < <(lsblk -lnpo NAME "$DEV" | tail -n +2)
if (( RESUME )); then
echo "== 3-5. resuming: reusing ${P[*]}"
mkdir -p "$R"
sudo mount "${P[1]}" "$R"
sudo mount "${P[0]}" "$R/boot/efi"
RUUID=$(lsblk -no UUID "${P[1]}"); EUUID=$(lsblk -no UUID "${P[0]}")
else
echo "== 3. partitions and filesystems on $DEV"
sudo wipefs -qa "$DEV"
sudo sfdisk -q "$DEV" <<'EOF'
label: gpt
size=512MiB, type=U, name="BOOK4-ESP"
size=8GiB,   type=L, name="BOOK4-RESCUE"
             type=L, name="BOOK4-BACKUP"
EOF
sudo udevadm settle
mapfile -t P < <(lsblk -lnpo NAME "$DEV" | tail -n +2)
(( ${#P[@]} == 3 )) || { echo "Expected 3 partitions on $DEV." >&2; exit 1; }
sudo mkfs.vfat -F 32 -n BOOK4ESP "${P[0]}" >/dev/null
sudo mkfs.ext4 -q -L BOOK4-RESCUE "${P[1]}"
sudo mkfs.btrfs -q -f -L BOOK4-BACKUP "${P[2]}"
sudo udevadm settle
RUUID=$(lsblk -no UUID "${P[1]}"); EUUID=$(lsblk -no UUID "${P[0]}")

echo "== 4. base system"
mkdir -p "$R"
sudo mount "${P[1]}" "$R"
sudo bsdtar -xpf "$CACHE/$TARBALL" -C "$R"     # bsdtar keeps file capabilities
sudo mkdir -p "$R/boot/efi"
sudo mount "${P[0]}" "$R/boot/efi"

echo "== 5. kernel modules, our firmware and config from this machine"
sudo cp -a "/usr/lib/modules/$K" "$R/usr/lib/modules/"
sudo mkdir -p "$R/usr/lib/firmware"
sudo cp -a /usr/lib/firmware/updates "$R/usr/lib/firmware/"
for f in /etc/modprobe.d/book4-*.conf /etc/modules-load.d/book4-*.conf /etc/udev/rules.d/*book4*.rules \
         /etc/vconsole.conf /etc/locale.conf /etc/pacman.d/mirrorlist; do
    [ -e "$f" ] && sudo install -D -m 644 "$f" "$R$f"
done
sudo ln -sf /usr/share/zoneinfo/"$(timedatectl show -p Timezone --value)" "$R/etc/localtime"
echo book4-rescue | sudo tee "$R/etc/hostname" >/dev/null
sudo tee "$R/etc/fstab" >/dev/null <<EOF
UUID=$RUUID  /           ext4  defaults,noatime              0 1
UUID=$EUUID  /boot/efi   vfat  defaults,umask=0077,nofail    0 2
LABEL=BOOK4-BACKUP  /mnt/backup  btrfs  noauto,compress=zstd:3  0 0
EOF
sudo mkdir -p "$R/mnt/backup" "$R/mnt/top" "$R/mnt/fboot" "$R/mnt/fesp"
# Initramfs: the USB-C host chain (samsung-emuec switches the port to host
# mode) and USB storage to find this root, UFS for the internal disk.
sudo install -D -m 644 /dev/stdin "$R/etc/mkinitcpio.conf.d/book4-rescue.conf" <<'EOF'
# Galaxy Book4 Edge rescue stick: no autodetect (built in a container).
MODULES=(dwc3 dwc3_qcom xhci_plat_hcd phy_qcom_qmp_combo phy_snps_eusb2 typec gpio_sbu_mux samsung_emuec
         usb_storage uas vfat ufs_qcom ufshcd_pltfrm phy_qcom_qmp_ufs)
HOOKS=(base systemd modconf block filesystems keyboard sd-vconsole fsck)
EOF
fi   # RESUME

E=$R/boot/efi
if (( ! GRUB_ONLY )); then
if (( RESUME )) && ls "$R"/var/lib/pacman/local/grub-[0-9]* >/dev/null 2>&1 && grep -q "^$U:" "$R/etc/passwd"; then
echo "== 6. packages and user already done"
else
echo "== 6. packages, user (inside the stick's system)"
ns /bin/bash -euc "
pacman-key --init >/dev/null
pacman-key --populate archlinuxarm >/dev/null
pacman -Q linux-aarch64 >/dev/null 2>&1 && pacman -Rdd --noconfirm linux-aarch64 >/dev/null
pacman -Syu --noconfirm
pacman -S --noconfirm --needed mkinitcpio linux-firmware-qcom networkmanager sudo btrfs-progs dosfstools \
    e2fsprogs gptfdisk zstd rsync git nano vim less grub
pacman -D --asexplicit mkinitcpio >/dev/null
locale-gen >/dev/null 2>&1 || true
depmod $K
systemctl enable NetworkManager >/dev/null
systemctl disable systemd-networkd systemd-networkd.socket >/dev/null 2>&1 || true
userdel -r alarm 2>/dev/null || true
id $U >/dev/null 2>&1 || useradd -m -G wheel -s /bin/bash $U
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel; chmod 440 /etc/sudoers.d/10-wheel
passwd -l root >/dev/null
"
fi
# Password only if none is set yet (resume after an interrupted prompt).
if sudo awk -F: -v u="$U" '$1 == u { exit !($2 == "" || $2 ~ /^!/) }' "$R/etc/shadow"; then
    echo "   password for $U on the stick:"
    ns passwd "$U"
else
    echo "   $U already has a password on the stick"
fi
sudo rm -rf "$R/home/$U/$(basename "$REPO")"
sudo cp -a "$REPO" "$R/home/$U/"
ns chown -R "$U:$U" "/home/$U/$(basename "$REPO")"

echo "== 7. initramfs, kernel and device tree onto the stick's ESP"
sudo mkdir -p "$E/book4"
ns mkinitcpio -k "$K" -g /boot/efi/book4/initramfs.img
LIST=$(ns lsinitcpio /boot/efi/book4/initramfs.img)
for m in samsung-emuec usb-storage dwc3-qcom ufs-qcom; do
    grep -qE "/$m\.ko" <<<"$LIST" || { echo "$m.ko missing from the initramfs." >&2; exit 1; }
done
# Checked from the host too: the ESP must have been mounted inside the container.
sudo test -s "$E/book4/initramfs.img" || { echo "initramfs did not land on the stick's ESP." >&2; exit 1; }
sudo install -m 644 "$M/fboot/vmlinuz-$K" "$E/book4/vmlinuz"
sudo install -m 644 "$M/fboot$DTB" "$E/book4/book4.dtb"

fi   # GRUB_ONLY

echo "== 8. GRUB (standalone image, built inside the stick's system)"
sudo touch "$E/book4-rescue.id"
sudo tee "$E/book4/grub.cfg" >/dev/null <<EOF
# Galaxy Book4 Edge 14" rescue stick ($(date +%F), kernel $K)
set timeout=5
set timeout_style=menu
set gfxpayload=keep
# Snapdragon X firmware memory-map workaround; without it this machine resets.
if [ "\$lockdown" != "y" ]; then
  cutmem 0x8800000000 0x8fffffffff
fi

menuentry "Book4 rescue (Arch Linux ARM, $K)" {
    devicetree /book4/book4.dtb
    linux  /book4/vmlinuz root=UUID=$RUUID rw rootwait$CMDLINE
    initrd /book4/initramfs.img
}
menuentry "Book4 rescue - verbose" {
    devicetree /book4/book4.dtb
    linux  /book4/vmlinuz root=UUID=$RUUID rw rootwait$CMDLINE earlycon keep_bootcon ignore_loglevel
    initrd /book4/initramfs.img
}
menuentry "UEFI Firmware Settings" { fwsetup }
EOF
# Not under /tmp: systemd-nspawn mounts an empty tmpfs there, and
# grub-mkstandalone then built an image without this file (stick stopped at
# a bare grub> prompt, 8 Oct).
sudo tee "$R/root/grub-embed.cfg" >/dev/null <<'EOF'
search --no-floppy --set=root --file /book4-rescue.id
set prefix=($root)/book4
configfile $prefix/grub.cfg
EOF
sudo mkdir -p "$E/EFI/BOOT"
ns grub-mkstandalone -O arm64-efi -o /boot/efi/EFI/BOOT/BOOTAA64.EFI \
    --modules="part_gpt fat search search_fs_file configfile linux fdt mmap efi_gop" \
    "boot/grub/grub.cfg=/root/grub-embed.cfg"
sudo rm -f "$R/root/grub-embed.cfg"
sudo test -s "$E/EFI/BOOT/BOOTAA64.EFI" || { echo "GRUB image did not land on the stick's ESP." >&2; exit 1; }
sudo grep -qa 'book4-rescue.id' "$E/EFI/BOOT/BOOTAA64.EFI" || { echo "GRUB image lacks its built-in config." >&2; exit 1; }
ns sh -c 'ls /usr/lib/grub/arm64-efi/ | grep -qx mmap.mod'   # provides cutmem

echo "== 9. done"
lsblk -o NAME,SIZE,FSTYPE,LABEL "$DEV"
sudo ls -l "$E/EFI/BOOT" "$E/book4"
echo
echo "Boot it: plug in, power on, choose the USB stick in the firmware's boot menu"
echo "(or \"UEFI Firmware Settings\" in the normal GRUB menu). Log in as $U."
echo "Backup onto its own partition: sudo mount /mnt/backup, then"
echo "  bash ~/$(basename "$REPO")/tools/backup/linux-backup.sh /mnt/backup"
