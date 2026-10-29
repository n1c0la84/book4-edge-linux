#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Private live/portable USB image of this Arch + Omarchy install for the
# Galaxy Book4 Edge 14": the whole system (packages, /etc, our kernel,
# modules and the Windows-extracted firmware) and the desktop customizations
# (Hyprland, Omarchy shell and plugins, terminals...), without personal files,
# secrets or Fedora. It boots from the stick on its own: its own GRUB with the
# cutmem workaround, kernel, initramfs and DTBs on the stick's ESP.
#
#   bash install/arch/live-image.sh build [IMG]        (default ~/book4-live.img)
#   bash install/arch/live-image.sh write IMG /dev/sdX (WIPES the stick)
#
# Run as your user on Arch (sudo inside), booted from el2-sleep (7.2.7-book4s
# at EL2): the image gets the running kernel, its two sleep DTBs from /boot
# (sda4) and the EL2 files from the internal ESP (\EFI\book4-el2\: UEFI Shell,
# qebspil, slbounce, tcblaunch.exe; \firmware\...). The image holds
# tcblaunch.exe (Microsoft's) and the Samsung/Qualcomm firmware: keep it
# private, never upload it.
#
# Not in the image: /home (except the whitelisted config below and a clone of
# this repo), Wi-Fi/VPN connections, Bluetooth pairings, fingerprints, SSH
# host keys, the pacman keyring's local key, journal, caches, other kernels.
# You set the user's password during the build; root stays locked; sshd off.
#
# Boot menu (stick's GRUB, from the firmware's boot menu, F10):
#   EL2 (default): GRUB -> UEFI Shell -> qebspil + slbounce -> second GRUB ->
#                  kernel at EL2 (deep sleep, KVM)
#   EL1:           kernel straight from the first GRUB (no deep sleep)
# Nothing is written to the internal disk, its ESP or the UEFI variables.
#
# Layout: 1 BOOK4LIVE 1 GiB FAT32 (boot files), 2 BOOK4-LIVE btrfs, subvolume
# arch (as on the internal disk), zstd. `write` grows partition 2 to the
# whole stick; the filesystem grows at first boot (x-systemd.growfs).
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
U=$(id -un)
K=${KVER:-$(uname -r)}
SIZE=${SIZE:-24G}
ROOT_UUID=4d74e1d5-7bca-48bf-a6e0-1362fd77882e                    # sda5 btrfs
DEV_BOOT=/dev/disk/by-uuid/3c3204e5-ed67-4e72-b0dc-75b7e3cdb3a5   # Fedora /boot (sda4)
DEV_ESP=/dev/disk/by-uuid/EE27-EF4A                               # internal ESP
EL2DIR=EFI/book4-el2
FWDIR=firmware/qcom/x1e80100/SAMSUNG/galaxy-book4-edge
KEEPALIVE=

(( EUID != 0 )) || { echo "Run as your user, not as root." >&2; exit 1; }
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }

usage() { sed -n '10,11p' "$0" | sed 's/^# //' >&2; exit 1; }

keep_sudo() {
    sudo -v
    ( while sleep 50; do sudo -n -v 2>/dev/null || exit; done ) &
    KEEPALIVE=$!
}

# Whole USB disk, not the running system's, nothing mounted.
check_stick() {
    local dev=$1 root_disk
    [ -b "$dev" ] && [ "$(lsblk -dno TYPE "$dev")" = disk ] || { echo "$dev is not a whole disk." >&2; exit 1; }
    root_disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE / | sed 's/\[.*//')")
    [ "$(basename "$dev")" != "$root_disk" ] || { echo "$dev holds the running system." >&2; exit 1; }
    [ "$(lsblk -dno TRAN "$dev")" = usb ] || { echo "$dev is not a USB disk." >&2; exit 1; }
    if lsblk -no MOUNTPOINTS "$dev" | grep -q .; then
        echo "$dev has mounted partitions; unmount them first:" >&2; lsblk "$dev" >&2; exit 1
    fi
}

cmd_write() {
    local img=${1:-} dev=${2:-} ok bytes esp_end
    [ -n "$img" ] && [ -n "$dev" ] || usage
    [ -s "$img" ] || { echo "$img not found." >&2; exit 1; }
    check_stick "$dev"
    bytes=$(stat -c %s "$img")
    (( $(lsblk -bdno SIZE "$dev") >= bytes )) ||
        { echo "$dev is smaller than the image ($(numfmt --to=iec "$bytes"))." >&2; exit 1; }
    lsblk -o NAME,SIZE,MODEL,TRAN,LABEL "$dev"
    read -r -p "Write $img to $dev ($(lsblk -dno SIZE "$dev") $(lsblk -dno MODEL "$dev")), erasing it? Type the device name ($dev): " ok
    [ "$ok" = "$dev" ] || { echo "Aborted."; exit 1; }
    keep_sudo
    trap 'kill $KEEPALIVE 2>/dev/null || true' EXIT
    esp_end=$(sfdisk -J "$img" | python3 -I -c 'import json,sys; p=json.load(sys.stdin)["partitiontable"]["partitions"][0]; print((p["start"]+p["size"])*512)')
    sudo wipefs -qa "$dev"
    # Partition table and ESP in full, then the btrfs partition sparse: its
    # free space is holes in the image and skipping it saves most of the
    # write. Stale data in the stick's unused blocks is never read.
    sudo dd if="$img" of="$dev" bs=1M count=$(( esp_end / 1048576 )) conv=fsync status=none
    sudo dd if="$img" of="$dev" bs=1M skip=$(( esp_end / 1048576 )) seek=$(( esp_end / 1048576 )) \
        conv=sparse,notrunc,fsync status=progress
    # The backup GPT to the real end of the stick, then partition 2 to the end.
    sudo sfdisk -q --relocate gpt-bak-std "$dev"
    echo ', +' | sudo sfdisk -q --no-reread -N 2 "$dev"
    sudo partprobe "$dev" 2>/dev/null || true
    sudo udevadm settle
    # Cheap sticks drop writes: compare the ESP (the partition table was
    # rewritten above).
    sudo cmp -n $(( esp_end - 1048576 )) -i 1048576 "$img" "$dev" ||
        { echo "error: the stick differs from the image in the boot partition; write it again." >&2; exit 1; }
    sync
    lsblk -o NAME,SIZE,FSTYPE,LABEL "$dev"
    echo "Done. Boot it with F10 (choose the USB stick). The root filesystem"
    echo "grows to the whole stick at the first boot."
}

cmd_build() {
    local img=${1:-$HOME/book4-live.img}
    local M R E TOP SNAP LOOP P1 P2 RUUID EUUID CMDLINE EL1ARGS EL2ARGS d

    echo "== 0. checks"
    [[ $(findmnt -n -o SOURCE /) == *"[/arch]" ]] || { echo "/ is not the arch subvolume." >&2; exit 1; }
    [ -d "/usr/lib/modules/$K" ] || { echo "No modules for $K." >&2; exit 1; }
    [ ! -e "$img" ] || { echo "$img exists; remove it first." >&2; exit 1; }
    for t in systemd-nspawn rsync losetup sfdisk mkfs.btrfs mkfs.vfat; do
        command -v $t >/dev/null || { echo "$t missing." >&2; exit 1; }
    done
    # Kernel arguments: the running EL2 entry's, minus its root. The EL1 entry
    # drops the EL2 timer flag and gets back the ignore_unused pair that
    # sleep-setup.sh removes for EL2.
    CMDLINE=$(sed -E 's/^BOOT_IMAGE=[^ ]+ //; s/(^| )root=[^ ]+//; s/(^| )rootflags=[^ ]+//; s/(^| )ro( |$)/ /' /proc/cmdline | tr -s ' ')
    [[ " $CMDLINE " == *" id_aa64mmfr0.ecv=1 "* ]] ||
        { echo "Boot the el2-sleep entry first (no id_aa64mmfr0.ecv=1 on this boot)." >&2; exit 1; }
    EL2ARGS=$CMDLINE
    EL1ARGS="$(sed -E 's/(^| )id_aa64mmfr0\.ecv=1//' <<<"$CMDLINE") clk_ignore_unused pd_ignore_unused"
    echo "   kernel $K"
    echo "   EL2:$EL2ARGS"
    echo "   EL1:$EL1ARGS"
    keep_sudo

    M=$(mktemp -d); R=$M/root; E=$R/boot/efi; TOP=$M/top
    SNAP=arch-live-src-$(date +%Y%m%d-%H%M%S)
    LOOP=
    ns() { sudo systemd-nspawn -q -D "$R" --resolv-conf=replace-uplink "$@"; }
    cleanup() {
        kill "$KEEPALIVE" 2>/dev/null || true
        sync
        for d in "$E" "$R" "$M/fboot" "$M/fesp"; do mountpoint -q "$d" && sudo umount "$d" || true; done
        [ -n "$LOOP" ] && sudo losetup -d "$LOOP" || true
        if mountpoint -q "$TOP"; then
            [ -d "$TOP/$SNAP" ] && sudo btrfs -q subvolume delete "$TOP/$SNAP" || true
            sudo umount "$TOP"
        fi
    }
    trap cleanup EXIT

    echo "== 1. inputs: kernel, DTBs (sda4), EL2 files (internal ESP)"
    mkdir -p "$M/fboot" "$M/fesp" "$TOP"
    sudo mount -o ro "$DEV_BOOT" "$M/fboot"
    sudo mount -o ro "$DEV_ESP" "$M/fesp"
    for f in "$M/fboot/vmlinuz-$K" "$M/fboot/dtb-test/book4-sleep.dtb" "$M/fboot/dtb-test/book4-sleep-el2.dtb" \
             "$M/fesp/$EL2DIR"/{Shellaa64.efi,qebspilaa64.efi,slbounce.efi,tcblaunch.exe} \
             "$M/fesp/$FWDIR"/{qcadsp8380.mbn,adsp_dtbs.elf,qccdsp8380.mbn,cdsp_dtbs.elf}; do
        sudo test -s "$f" || { echo "missing: ${f#$M/}" >&2; exit 1; }
    done

    echo "== 2. image $img ($SIZE, sparse)"
    truncate -s "$SIZE" "$img"
    sfdisk -q "$img" <<'EOF'
label: gpt
size=1GiB, type=U, name="BOOK4-ESP"
           type=L, name="BOOK4-LIVE"
EOF
    LOOP=$(sudo losetup -fP --show "$img")
    P1=${LOOP}p1; P2=${LOOP}p2
    sudo udevadm settle
    sudo mkfs.vfat -F 32 -n BOOK4LIVE "$P1" >/dev/null
    sudo mkfs.btrfs -q -f -L BOOK4-LIVE "$P2"
    RUUID=$(sudo blkid -s UUID -o value "$P2"); EUUID=$(sudo blkid -s UUID -o value "$P1")
    mkdir -p "$R"
    sudo mount -o compress=zstd:3 "$P2" "$R"
    sudo btrfs -q subvolume create "$R/arch"
    sudo umount "$R"
    sudo mount -o compress=zstd:3,noatime,subvol=arch "$P2" "$R"

    echo "== 3. system, from a read-only snapshot of the arch subvolume"
    sudo mount -o subvolid=5 "UUID=$ROOT_UUID" "$TOP"
    sudo btrfs -q subvolume snapshot -r "$TOP/arch" "$TOP/$SNAP"
    set -f   # patterns for rsync, not for this shell
    local ex=(/home/* /root/* /tmp/* /var/tmp/* /var/cache/* /boot/* /swap /swapfile /.snapshots /lost+found
        /var/log/journal/* '/var/log/*.log' '/var/log/*.log.*' '/var/log/*.old' /var/lib/systemd/coredump/*
        /var/lib/systemd/random-seed /var/lib/systemd/credential.secret /var/lib/systemd/pstore/*
        /var/lib/fprint/* /var/lib/bluetooth/* /var/lib/NetworkManager/* /etc/NetworkManager/system-connections/*
        /var/lib/iwd/* /var/lib/dhcpcd/* /var/lib/upower/* /var/lib/tpm2-tss/* /var/lib/private/*
        /var/lib/machines/* /var/lib/docker/* /var/lib/containerd/* /var/lib/libvirt/images/* /var/lib/plocate/*
        /var/lib/book4/staged /etc/ssh/ssh_host_* /etc/pacman.d/gnupg/* /etc/machine-id)
    set +f
    for d in /usr/lib/modules/*; do [ "$(basename "$d")" = "$K" ] || ex+=("$d"); done
    sudo rsync -aHAX --numeric-ids --info=progress2 "${ex[@]/#/--exclude=}" "$TOP/$SNAP/" "$R/"
    sudo btrfs -q subvolume delete "$TOP/$SNAP"

    echo "== 4. home: desktop customizations only"
    local H=$R/home/$U
    local cfg=(alacritty autostart btop fastfetch fcitx fcitx5 fontconfig foot ghostty gtk-3.0 hypr
        hyprland-preview-share-picker imv kitty lazygit mpv nautilus omarchy pipewire procps systemd tmux
        wireplumber xournalpp dconf mise chrome-flags.conf chromium-flags.conf mimeapps.list starship.toml
        user-dirs.dirs user-dirs.locale)
    sudo install -d -o "$U" -g "$U" -m 700 "$H" "$H/.config" "$H/.local" "$H/.local/share" "$H/.local/state" "$H/.local/bin"
    for d in "${cfg[@]}"; do
        [ -e "$HOME/.config/$d" ] && sudo rsync -aHAX "$HOME/.config/$d" "$H/.config/" \
            --exclude='/omarchy/shell.json.bak*' --exclude='/systemd/user/llama-server.service' \
            --exclude='/systemd/user/*.wants/llama-server.service'
    done
    for d in applications icons nicola-ytmusic mimeapps.list; do
        [ -e "$HOME/.local/share/$d" ] && sudo rsync -aHAX "$HOME/.local/share/$d" "$H/.local/share/"
    done
    [ -d "$HOME/.local/state/omarchy" ] && sudo rsync -aHAX "$HOME/.local/state/omarchy" "$H/.local/state/" \
        --exclude='/omarchy/clipboard-history.json' --exclude='/omarchy/clipboard-images' \
        --exclude='/omarchy/notifications' --exclude='/omarchy/agents' --exclude='/omarchy/first-run.log'
    for f in "$HOME"/.local/bin/book4-*; do [ -e "$f" ] && sudo cp -a "$f" "$H/.local/bin/"; done
    for f in .bashrc .bash_profile .bash_logout .XCompose; do
        [ -e "$HOME/$f" ] && sudo cp -a "$HOME/$f" "$H/"
    done
    # This repo as a clean clone (tracked files only), remote kept.
    git clone -q --no-hardlinks "$REPO" "$M/repo"
    git -C "$M/repo" remote set-url origin "$(git -C "$REPO" remote get-url origin)"
    sudo install -d -o "$U" -g "$U" "$H/Projects"
    sudo cp -a "$M/repo" "$H/Projects/$(basename "$REPO")"
    rm -rf "$M/repo"
    sudo chown -R --reference="$HOME" "$H"

    echo "== 5. configuration for the stick"
    systemd-id128 new | sudo tee "$R/etc/machine-id" >/dev/null
    echo book4-live | sudo tee "$R/etc/hostname" >/dev/null
    sudo tee "$R/etc/fstab" >/dev/null <<EOF
# Book4 live stick (install/arch/live-image.sh, $(date +%F))
UUID=$RUUID  /          btrfs  rw,noatime,compress=zstd:3,subvol=/arch,x-systemd.growfs  0 0
UUID=$EUUID  /boot/efi  vfat   defaults,umask=0077,nofail                                0 2
EOF
    sudo mkdir -p "$E"
    sudo mount "$P1" "$E"
    # Initramfs: the USB-C host chain (samsung-emuec switches the port to host
    # mode) and USB storage to find this root (btrfs is built in), UFS for the internal disk.
    # Sorts after book4.conf, so its MODULES/HOOKS win.
    sudo install -D -m 644 /dev/stdin "$R/etc/mkinitcpio.conf.d/book4-live.conf" <<'EOF'
# Galaxy Book4 Edge live stick: no autodetect (built in a container).
MODULES=(dwc3 dwc3_qcom xhci_plat_hcd phy_qcom_qmp_combo phy_snps_eusb2 typec gpio_sbu_mux samsung_emuec
         usb_storage uas vfat ufs_qcom ufshcd_pltfrm phy_qcom_qmp_ufs)
HOOKS=(base systemd modconf block filesystems keyboard sd-vconsole fsck)
EOF
    echo "   password for $U on the stick:"
    ns passwd "$U"
    ns /bin/bash -euc "
passwd -l root >/dev/null
pacman-key --init >/dev/null 2>&1
pacman-key --populate archlinuxarm omarchy >/dev/null 2>&1
pacman -S --noconfirm --needed grub >/dev/null
systemctl disable sshd >/dev/null 2>&1 || true
"
    if sudo grep -rIl "$ROOT_UUID" "$R/etc" 2>/dev/null; then
        echo "   WARNING: the files above still name the internal root filesystem."
    fi

    echo "== 6. boot files on the stick's ESP"
    sudo mkdir -p "$E/book4" "$E/EFI/BOOT" "$E/EFI/book4-live" "$E/$EL2DIR" "$E/$FWDIR"
    ns mkinitcpio -k "$K" -g /boot/efi/book4/initramfs.img
    local list
    list=$(ns --pipe lsinitcpio /boot/efi/book4/initramfs.img | tr -d '\r')
    for m in samsung-emuec usb-storage dwc3-qcom; do
        grep -qE "/$m\.ko" <<<"$list" || { echo "$m.ko missing from the initramfs." >&2; exit 1; }
    done
    sudo install -m 644 "$M/fboot/vmlinuz-$K" "$E/book4/vmlinuz"
    sudo install -m 644 "$M/fboot/dtb-test/book4-sleep.dtb" "$E/book4/book4-el1.dtb"
    sudo install -m 644 "$M/fboot/dtb-test/book4-sleep-el2.dtb" "$E/book4/book4-el2.dtb"
    for f in Shellaa64.efi qebspilaa64.efi slbounce.efi tcblaunch.exe; do
        sudo install -m 644 "$M/fesp/$EL2DIR/$f" "$E/$EL2DIR/$f"
    done
    sudo install -m 644 "$M/fesp/$EL2DIR/tcblaunch.exe" "$E/tcblaunch.exe"
    sudo install -m 644 "$REPO/install/el2/startup-live.nsh" "$E/$EL2DIR/startup.nsh"
    sudo cp "$M/fesp/$FWDIR"/* "$E/$FWDIR/"
    sudo touch "$E/book4-live.id"
    sudo tee "$E/book4/grub.cfg" >/dev/null <<EOF
# Galaxy Book4 Edge 14" live stick ($(date +%F), kernel $K)
set timeout=5
set timeout_style=menu
set gfxpayload=keep
# Snapdragon X firmware memory-map workaround; without it this machine resets.
if [ "\$lockdown" != "y" ]; then
  cutmem 0x8800000000 0x8fffffffff
fi

if [ "\$book4_el2" = 1 ]; then
  # Second GRUB, after the UEFI Shell loaded qebspil and slbounce.
  set timeout=1
  menuentry "Book4 live - EL2 ($K)" {
      devicetree /book4/book4-el2.dtb
      linux  /book4/vmlinuz root=UUID=$RUUID rootflags=subvol=arch rw rootwait$EL2ARGS
      initrd /book4/initramfs.img
  }
else
  menuentry "Book4 live - EL2 (deep sleep; via UEFI Shell + slbounce)" {
      chainloader /$EL2DIR/Shellaa64.efi
  }
  menuentry "Book4 live - EL1 (no deep sleep)" {
      devicetree /book4/book4-el1.dtb
      linux  /book4/vmlinuz root=UUID=$RUUID rootflags=subvol=arch rw rootwait $EL1ARGS
      initrd /book4/initramfs.img
  }
  menuentry "Book4 live - EL1, verbose" {
      devicetree /book4/book4-el1.dtb
      linux  /book4/vmlinuz root=UUID=$RUUID rootflags=subvol=arch rw rootwait $EL1ARGS earlycon keep_bootcon ignore_loglevel
      initrd /book4/initramfs.img
  }
  menuentry "UEFI Firmware Settings" { fwsetup }
fi
EOF
    # Not under /tmp: systemd-nspawn mounts an empty tmpfs there.
    sudo tee "$R/root/grub-embed.cfg" >/dev/null <<'EOF'
search --no-floppy --set=root --file /book4-live.id
set prefix=($root)/book4
configfile $prefix/grub.cfg
EOF
    sudo tee "$R/root/grub-embed-el2.cfg" >/dev/null <<'EOF'
search --no-floppy --set=root --file /book4-live.id
set prefix=($root)/book4
set book4_el2=1
export book4_el2
configfile $prefix/grub.cfg
EOF
    local mods="part_gpt fat search search_fs_file configfile linux fdt mmap efi_gop chain test"
    ns grub-mkstandalone -O arm64-efi -o /boot/efi/EFI/BOOT/BOOTAA64.EFI --modules="$mods" \
        "boot/grub/grub.cfg=/root/grub-embed.cfg"
    ns grub-mkstandalone -O arm64-efi -o /boot/efi/EFI/book4-live/grub-el2.efi --modules="$mods" \
        "boot/grub/grub.cfg=/root/grub-embed-el2.cfg"
    sudo rm -f "$R/root/grub-embed.cfg" "$R/root/grub-embed-el2.cfg"
    for f in EFI/BOOT/BOOTAA64.EFI EFI/book4-live/grub-el2.efi; do
        sudo grep -qa 'book4-live.id' "$E/$f" || { echo "$f lacks its built-in config." >&2; exit 1; }
    done

    echo "== 7. done"
    sudo btrfs filesystem usage -h "$R" | grep -E '^\s+(Used|Free \(estimated\))'
    sudo du -sh "$E"
    sudo find "$E" -type f | sed "s|^$E||" | sort
    echo
    echo "Image: $img (sparse; $(du -h "$img" | cut -f1) on disk). Keep it private."
    echo "Write it: bash $0 write $img /dev/sdX"
}

case ${1:-} in
    build) shift; cmd_build "$@" ;;
    write) shift; cmd_write "$@" ;;
    *) usage ;;
esac
