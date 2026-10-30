#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Private live ISO of this Arch + Omarchy install for the Galaxy Book4 Edge
# 14": the whole system (packages, /etc, our kernel, modules and the
# Windows-extracted firmware) and the desktop customizations (Hyprland,
# Omarchy shell and plugins, terminals...), without personal files, secrets
# or Fedora. A read-only squashfs with a tmpfs overlay (changes are lost at
# power-off), its own boot chain (install/arch/lib/book4-grub.sh) and an
# installer that wipes Linux on the internal disk and puts this system there
# (sudo book4-install; install/arch/book4-install.sh).
#
#   bash install/arch/live-iso.sh build [ISO]          (default ~/book4-live.iso)
#   bash install/arch/live-iso.sh write ISO /dev/sdX   (WIPES the stick)
#
# Run as your user on Arch (sudo inside), booted from el2-sleep (7.2.7-book4s
# at EL2): the ISO gets the running kernel, its two sleep DTBs from /boot
# (sda4) and the EL2 files from the internal ESP (\EFI\book4-el2\: UEFI Shell,
# qebspil, slbounce, tcblaunch.exe; \firmware\...). Needs squashfs-tools,
# libisoburn and mtools. The ISO holds tcblaunch.exe (Microsoft's) and the
# Samsung/Qualcomm firmware: keep it private, never upload it.
#
# Not in the ISO: /home (except the whitelisted config below and a clone of
# this repo), Wi-Fi/VPN connections, Bluetooth pairings, fingerprints, SSH
# host keys, the pacman keyring's local key, journal, caches, other kernels.
# You set the user's password during the build; root stays locked; sshd off.
#
# Boot menu (F10, the USB stick):
#   EL2 (default): GRUB -> UEFI Shell -> qebspil + slbounce -> second GRUB ->
#                  kernel at EL2 (deep sleep, KVM)
#   EL1:           kernel straight from the first GRUB (no deep sleep)
# Booting the ISO writes nothing to the internal disk, its ESP or the UEFI
# variables. The work tree (~/src/book4-iso) is kept: rebuilds only copy
# what changed.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
U=$(id -un)
K=${KVER:-$(uname -r)}
W=${WORK:-$HOME/src/book4-iso}
LABEL=BOOK4_LIVE
ROOT_UUID=4d74e1d5-7bca-48bf-a6e0-1362fd77882e                    # sda5 btrfs
DEV_BOOT=/dev/disk/by-uuid/3c3204e5-ed67-4e72-b0dc-75b7e3cdb3a5   # Fedora /boot (sda4)
DEV_ESP=/dev/disk/by-uuid/EE27-EF4A                               # internal ESP
EL2DIR=EFI/book4-el2
FWDIR=firmware/qcom/x1e80100/SAMSUNG/galaxy-book4-edge
KEEPALIVE=
# shellcheck source=lib/book4-grub.sh
. "$REPO/install/arch/lib/book4-grub.sh"

(( EUID != 0 )) || { echo "Run as your user, not as root." >&2; exit 1; }
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }

usage() { sed -n '12,13p' "$0" | sed 's/^# //' >&2; exit 1; }

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
    local iso=${1:-} dev=${2:-} ok bytes
    [ -n "$iso" ] && [ -n "$dev" ] || usage
    [ -s "$iso" ] || { echo "$iso not found." >&2; exit 1; }
    check_stick "$dev"
    bytes=$(stat -c %s "$iso")
    (( $(lsblk -bdno SIZE "$dev") >= bytes )) ||
        { echo "$dev is smaller than the ISO ($(numfmt --to=iec "$bytes"))." >&2; exit 1; }
    lsblk -o NAME,SIZE,MODEL,TRAN,LABEL "$dev"
    read -r -p "Write $iso to $dev ($(lsblk -dno SIZE "$dev") $(lsblk -dno MODEL "$dev")), erasing it? Type the device name ($dev): " ok
    [ "$ok" = "$dev" ] || { echo "Aborted."; exit 1; }
    keep_sudo
    trap 'kill $KEEPALIVE 2>/dev/null || true' EXIT
    sudo wipefs -qa "$dev"
    sudo dd if="$iso" of="$dev" bs=4M conv=fsync oflag=direct status=progress
    sudo udevadm settle
    # Cheap sticks drop writes: read it all back.
    echo "verifying..."
    sudo cmp -n "$bytes" "$iso" "$dev" || { echo "error: the stick differs from the ISO; write it again." >&2; exit 1; }
    lsblk -o NAME,SIZE,FSTYPE,LABEL "$dev"
    echo "Done, verified. Boot it with F10 (choose the USB stick)."
}

cmd_build() {
    local out=${1:-$HOME/book4-live.iso}
    local CMDLINE EL1ARGS EL2ARGS d f
    # Global, not local: cleanup() runs from the EXIT trap, after this
    # function has returned.
    M= A= E= TOP= SNAP=

    echo "== 0. checks"
    [[ $(findmnt -n -o SOURCE /) == *"[/arch]" ]] || { echo "/ is not the arch subvolume." >&2; exit 1; }
    [ -d "/usr/lib/modules/$K" ] || { echo "No modules for $K." >&2; exit 1; }
    for t in systemd-nspawn rsync mksquashfs xorriso mkfs.vfat mcopy systemd-id128; do
        command -v $t >/dev/null || { echo "$t missing (sudo pacman -S squashfs-tools libisoburn mtools)." >&2; exit 1; }
    done
    # Kernel arguments: the running EL2 entry's, minus its root. The EL1 entry
    # drops the EL2 timer flag and gets back the ignore_unused pair that
    # sleep-setup.sh removes for EL2.
    CMDLINE=$(sed -E 's/^BOOT_IMAGE=[^ ]+ //; s/(^| )root=[^ ]+//; s/(^| )rootflags=[^ ]+//; s/(^| )ro( |$)/ /' /proc/cmdline | tr -s ' ')
    [[ " $CMDLINE " == *" id_aa64mmfr0.ecv=1 "* ]] ||
        { echo "Boot the el2-sleep entry first (no id_aa64mmfr0.ecv=1 on this boot)." >&2; exit 1; }
    EL2ARGS=$(echo $CMDLINE)
    EL1ARGS=$(echo $(sed -E 's/(^| )id_aa64mmfr0\.ecv=1//' <<<"$CMDLINE") clk_ignore_unused pd_ignore_unused)
    echo "   kernel $K"
    echo "   EL2: $EL2ARGS"
    echo "   EL1: $EL1ARGS"
    keep_sudo

    M=$(mktemp -d); A=$W/airootfs; E=$W/efi; TOP=$M/top
    SNAP=arch-live-src-$(date +%Y%m%d-%H%M%S)
    ns() { sudo systemd-nspawn -q -D "$A" --resolv-conf=replace-uplink "$@"; }
    cleanup() {
        kill "$KEEPALIVE" 2>/dev/null || true
        for d in "$M/fboot" "$M/fesp"; do mountpoint -q "$d" && sudo umount "$d" || true; done
        if mountpoint -q "$TOP"; then
            [ -d "$TOP/$SNAP" ] && sudo btrfs -q subvolume delete "$TOP/$SNAP" || true
            sudo umount "$TOP"
        fi
        rm -rf "$M/repo"; rmdir "$M"/* "$M" 2>/dev/null || true
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

    echo "== 2. system, from a read-only snapshot of the arch subvolume -> $A"
    sudo mount -o subvolid=5 "UUID=$ROOT_UUID" "$TOP"
    sudo btrfs -q subvolume snapshot -r "$TOP/arch" "$TOP/$SNAP"
    # /var/log: the directories only (services expect them), no file: the
    # crash-log copies in book4-live/, the sleep CSV and wtmp are this
    # machine's history.
    set -f   # patterns for rsync, not for this shell
    local ex=(/home/* /root/* /tmp/* /var/tmp/* /var/cache/* /boot/* /swap /swapfile /.snapshots /lost+found
        /var/log/** /var/lib/systemd/coredump/*
        /var/lib/systemd/random-seed /var/lib/systemd/credential.secret /var/lib/systemd/pstore/*
        /var/lib/fprint/* /var/lib/bluetooth/* /var/lib/NetworkManager/* /etc/NetworkManager/system-connections/*
        /var/lib/iwd/* /var/lib/dhcpcd/* /var/lib/upower/* /var/lib/tpm2-tss/* /var/lib/private/*
        /var/lib/machines/* /var/lib/docker/* /var/lib/containerd/* /var/lib/libvirt/images/* /var/lib/plocate/*
        /var/lib/book4/staged /etc/ssh/ssh_host_* /etc/pacman.d/gnupg/* /etc/machine-id)
    set +f
    for d in /usr/lib/modules/*; do [ "$(basename "$d")" = "$K" ] || ex+=("$d"); done
    sudo mkdir -p "$A"
    sudo rsync -aHAX --numeric-ids --delete --delete-excluded --info=progress2 \
        --include='/var/log/**/' "${ex[@]/#/--exclude=}" "$TOP/$SNAP/" "$A/"
    sudo btrfs -q subvolume delete "$TOP/$SNAP"

    echo "== 3. home: desktop customizations only"
    local H=$A/home/$U
    local cfg=(alacritty autostart btop fastfetch fcitx fcitx5 fontconfig foot ghostty gtk-3.0 hypr
        hyprland-preview-share-picker imv kitty lazygit mpv nautilus omarchy pipewire procps systemd tmux
        wireplumber xournalpp dconf mise chrome-flags.conf chromium-flags.conf mimeapps.list starship.toml
        user-dirs.dirs user-dirs.locale)
    sudo install -d -m 700 "$H" "$H/.config" "$H/.local" "$H/.local/share" "$H/.local/state" "$H/.local/bin"
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
    sudo mkdir -p "$H/Projects"
    sudo cp -a "$M/repo" "$H/Projects/$(basename "$REPO")"
    sudo chown -R --reference="$HOME" "$H"

    echo "== 4. live configuration"
    sudo truncate -s 0 "$A/etc/machine-id"      # a new one at every live boot
    echo book4-live | sudo tee "$A/etc/hostname" >/dev/null
    printf '# Live ISO: the root is an overlay set up by the initramfs (book4live hook).\n' |
        sudo tee "$A/etc/fstab" >/dev/null
    echo "   password for $U (live session and installed system):"
    ns passwd "$U"
    ns /bin/bash -euc "
passwd -l root >/dev/null
pacman-key --init >/dev/null 2>&1
pacman-key --populate archlinuxarm omarchy >/dev/null 2>&1
"
    # Keys this machine added by hand for third-party repos (e.g.
    # openai-chatgpt): without them pacman rejects those databases. Every
    # public key of the host's keyring that the fresh one lacks, except the
    # host's own master key, is imported and locally signed.
    fprs() {
        sudo gpg --homedir "$1" --batch --with-colons --list-keys 2>/dev/null | awk -F: '
            $1 == "pub" { want = 1; next }
            want && $1 == "fpr" { f = $10; want = 0 }
            $1 == "uid" && f != "" { if ($10 !~ /Pacman Keyring Master Key/) print f; f = "" }' | sort -u
    }
    local extra
    extra=$(comm -23 <(fprs /etc/pacman.d/gnupg) <(fprs "$A/etc/pacman.d/gnupg"))
    if [ -n "$extra" ]; then
        # shellcheck disable=SC2086
        sudo gpg --homedir /etc/pacman.d/gnupg --batch --armor --export $extra | sudo tee "$A/root/extra-keys.asc" >/dev/null
        ns pacman-key --add /root/extra-keys.asc >/dev/null 2>&1
        for f in $extra; do ns pacman-key --lsign-key "$f" >/dev/null 2>&1; done
        sudo rm -f "$A/root/extra-keys.asc"
        echo "   third-party pacman keys carried over: $(wc -w <<<"$extra")"
    fi
    ns /bin/bash -euc "
pacman -S --noconfirm --needed grub squashfs-tools efibootmgr dosfstools rsync >/dev/null
systemctl disable sshd >/dev/null 2>&1 || true
"
    if sudo grep -rIl "$ROOT_UUID" "$A/etc" 2>/dev/null; then
        echo "   WARNING: the files above still name the internal root filesystem."
    fi

    echo "== 5. boot files, installer"
    # In the system too: the installer puts them on the internal disk.
    sudo install -D -m 644 "$M/fboot/vmlinuz-$K" "$A/boot/book4/vmlinuz"
    sudo install -D -m 644 "$M/fboot/dtb-test/book4-sleep.dtb" "$A/boot/book4/book4-el1.dtb"
    sudo install -D -m 644 "$M/fboot/dtb-test/book4-sleep-el2.dtb" "$A/boot/book4/book4-el2.dtb"
    for f in Shellaa64.efi qebspilaa64.efi slbounce.efi tcblaunch.exe; do
        sudo install -D -m 644 "$M/fesp/$EL2DIR/$f" "$A/usr/lib/book4/efi/$f"
    done
    sudo install -D -m 644 "$REPO/install/arch/lib/book4-grub.sh" "$A/usr/local/lib/book4/book4-grub.sh"
    sudo install -D -m 644 "$REPO/install/el2/startup-installed.nsh" "$A/usr/local/lib/book4/startup-installed.nsh"
    sudo install -D -m 755 "$REPO/install/arch/book4-install.sh" "$A/usr/local/sbin/book4-install"
    printf 'KVER=%q\nEL2ARGS=%q\nEL1ARGS=%q\nHOST_NAME=%q\n' "$K" "$EL2ARGS" "$EL1ARGS" "$(cat /etc/hostname)" |
        sudo install -D -m 644 /dev/stdin "$A/usr/local/lib/book4/kernel-args"
    sudo install -D -m 644 "$REPO/userspace/initcpio/hooks/book4live" "$A/etc/initcpio/hooks/book4live"
    sudo install -D -m 644 "$REPO/userspace/initcpio/install/book4live" "$A/etc/initcpio/install/book4live"
    # Live initramfs: busybox init with the book4live hook; the USB-C host
    # chain (samsung-emuec switches the port to host mode) and USB storage to
    # find the ISO, UFS for the internal disk. Sorts after book4.conf, so its
    # MODULES/HOOKS win; the installer removes it.
    sudo install -D -m 644 /dev/stdin "$A/etc/mkinitcpio.conf.d/book4-live.conf" <<'EOF'
# Galaxy Book4 Edge live ISO (removed by book4-install).
MODULES=(dwc3 dwc3_qcom xhci_plat_hcd phy_qcom_qmp_combo phy_snps_eusb2 typec gpio_sbu_mux samsung_emuec
         usb_storage uas vfat ufs_qcom ufshcd_pltfrm phy_qcom_qmp_ufs)
HOOKS=(base udev modconf block keyboard book4live)
EOF

    echo "== 6. ESP of the ISO"
    sudo rm -rf "$E"
    sudo mkdir -p "$E/book4" "$E/EFI/BOOT" "$E/EFI/book4-live" "$E/$EL2DIR" "$E/$FWDIR"
    ns mkinitcpio -k "$K" -g /root/initramfs-live.img
    local list
    list=$(ns --pipe lsinitcpio /root/initramfs-live.img | tr -d '\r')
    for m in samsung-emuec usb-storage dwc3-qcom isofs squashfs overlay loop; do
        grep -qE "/$m\.ko" <<<"$list" || { echo "$m.ko missing from the initramfs." >&2; exit 1; }
    done
    grep -q 'hooks/book4live' <<<"$list" || { echo "book4live hook missing from the initramfs." >&2; exit 1; }
    sudo mv "$A/root/initramfs-live.img" "$E/book4/initramfs.img"
    sudo cp "$A/boot/book4/"{vmlinuz,book4-el1.dtb,book4-el2.dtb} "$E/book4/"
    sudo cp "$A/usr/lib/book4/efi/"* "$E/$EL2DIR/"
    sudo cp "$A/usr/lib/book4/efi/tcblaunch.exe" "$E/tcblaunch.exe"
    sudo install -m 644 "$REPO/install/el2/startup-live.nsh" "$E/$EL2DIR/startup.nsh"
    sudo cp "$M/fesp/$FWDIR"/* "$E/$FWDIR/"
    sudo touch "$E/book4-live.id"
    book4_grub_cfg "Book4 live" "$K" /book4 "book4live=$LABEL" "$EL2ARGS" "$EL1ARGS" |
        sudo tee "$E/book4/grub.cfg" >/dev/null
    # Not under /tmp: systemd-nspawn mounts an empty tmpfs there.
    book4_grub_embed 'search --no-floppy --set=root --file /book4-live.id' 'set esp=$root' '($root)/book4' |
        sudo tee "$A/root/embed.cfg" >/dev/null
    book4_grub_embed 'search --no-floppy --set=root --file /book4-live.id' 'set esp=$root' '($root)/book4' el2 |
        sudo tee "$A/root/embed-el2.cfg" >/dev/null
    ns grub-mkstandalone -O arm64-efi -o /root/BOOTAA64.EFI --modules="$BOOK4_GRUB_MODULES" "boot/grub/grub.cfg=/root/embed.cfg"
    ns grub-mkstandalone -O arm64-efi -o /root/grub-el2.efi --modules="$BOOK4_GRUB_MODULES" "boot/grub/grub.cfg=/root/embed-el2.cfg"
    sudo mv "$A/root/BOOTAA64.EFI" "$E/EFI/BOOT/BOOTAA64.EFI"
    sudo mv "$A/root/grub-el2.efi" "$E/EFI/book4-live/grub-el2.efi"
    sudo rm -f "$A/root/embed.cfg" "$A/root/embed-el2.cfg"
    for f in EFI/BOOT/BOOTAA64.EFI EFI/book4-live/grub-el2.efi; do
        sudo grep -qa 'book4-live.id' "$E/$f" || { echo "$f lacks its built-in config." >&2; exit 1; }
    done
    local kb
    kb=$(( $(sudo du -sk "$E" | cut -f1) + 32768 ))
    sudo rm -f "$W/efiboot.img"
    sudo mkfs.vfat -C -n BOOK4LIVE "$W/efiboot.img" "$kb" >/dev/null
    sudo mcopy -s -i "$W/efiboot.img" "$E"/* ::/
    sudo mdir -i "$W/efiboot.img" ::/book4-live.id >/dev/null || { echo "efiboot.img is incomplete." >&2; exit 1; }

    echo "== 7. squashfs (zstd; takes a while)"
    sudo mkdir -p "$W/iso/live"
    sudo rm -f "$W/iso/live/airootfs.sfs"
    sudo mksquashfs "$A" "$W/iso/live/airootfs.sfs" -noappend -comp zstd -Xcompression-level 15 -b 1M -no-recovery

    echo "== 8. ISO $out"
    rm -f "$out"
    # UEFI only: the ESP image is appended as a GPT partition (as archiso does),
    # so the same file boots from a stick written with dd.
    xorriso -as mkisofs -iso-level 3 -full-iso9660-filenames -rational-rock -volid "$LABEL" \
        -appid "Galaxy Book4 Edge live ($K)" \
        -partition_offset 16 -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B "$W/efiboot.img" \
        -appended_part_as_gpt -e --interval:appended_partition_2:all:: -no-emul-boot \
        -o "$out" "$W/iso" 2>&1 | grep -vE '^xorriso : UPDATE|^Drive current|^Media current|^Media status' || true
    [ -s "$out" ] || { echo "xorriso failed." >&2; exit 1; }
    sudo rm -f "$W/iso/live/airootfs.sfs"     # the ISO holds it; the work tree keeps airootfs/
    (cd "$(dirname "$out")" && sha256sum "$(basename "$out")" > "$(basename "$out").sha256")

    echo "== 9. done"
    ls -lh "$out"
    echo "Keep it private (tcblaunch.exe, Windows firmware). Write it to a stick:"
    echo "  bash $0 write $out /dev/sdX"
}

case ${1:-} in
    build) shift; cmd_build "$@" ;;
    write) shift; cmd_write "$@" ;;
    *) usage ;;
esac
