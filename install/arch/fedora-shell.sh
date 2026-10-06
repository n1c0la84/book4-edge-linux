#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# From Arch: run Fedora's own tools (kernel tree, module builds, dracut, the
# GRUB boot hook, everything in install/) in a Fedora container, so kernel
# and boot work does not need a reboot into Fedora. Run as your user on Arch.
#
#   bash install/arch/fedora-shell.sh                 # interactive Fedora shell
#   bash install/arch/fedora-shell.sh CMD [ARGS...]    # run one command in it
#   bash install/arch/fedora-shell.sh --sync-modules [KVER]
#        copy KVER's modules (default: Fedora's pinned kernel) from Fedora into
#        this running Arch, rebuild Arch's initramfs and regenerate GRUB; the
#        Arch-side counterpart of install/arch/sync-kernel.sh.
#
# Inside the container you are your Fedora user in your Fedora home; sudo
# asks for your Fedora password. Fedora's /boot and the ESP are mounted
# there as on Fedora, so the scripts in install/ work unchanged (except
# install/arch/sync-kernel.sh, which expects Arch not to be running: use
# --sync-modules here instead).
#
# Rules as on Fedora: nothing is ever deleted from the ESP; a rebuilt Fedora
# initramfs keeps its .prev copy, so boot Fedora once after such a change.
set -euo pipefail
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
DEV_ROOT=/dev/disk/by-uuid/4d74e1d5-7bca-48bf-a6e0-1362fd77882e   # btrfs (sda5)
DEV_BOOT=/dev/disk/by-uuid/3c3204e5-ed67-4e72-b0dc-75b7e3cdb3a5   # Fedora /boot (sda4)
DEV_ESP=/dev/disk/by-uuid/EE27-EF4A                               # ESP (sda1), shared with Windows
M=/mnt/fedora
USER_NAME=${SUDO_USER:-$USER}
HOOK=/etc/kernel/install.d/99-book4-devicetree.install

sudo -v
mounts() {
    sudo mkdir -p $M/root $M/home $M/boot $M/esp
    mountpoint -q $M/root || sudo mount -o subvol=root,compress=zstd:1 $DEV_ROOT $M/root
    mountpoint -q $M/home || sudo mount -o subvol=home,compress=zstd:1 $DEV_ROOT $M/home
    mountpoint -q $M/boot || sudo mount $DEV_BOOT $M/boot
    mountpoint -q $M/esp  || sudo mount -o umask=0077,shortname=winnt $DEV_ESP $M/esp
    [ -e $M/root/etc/fedora-release ] || { echo "$M/root is not Fedora" >&2; exit 1; }
}
unmounts() {
    sync
    for d in esp boot home root; do mountpoint -q $M/$d && sudo umount $M/$d || true; done
}
fedora() {  # run "$@" in the Fedora container, as root unless -u is given first
    # Output to a file or pipe: --pipe passes stdin/stdout/stderr straight
    # through (no pseudo-terminal, so no pager, no CR line endings, and
    # stderr stays apart from stdout).
    local pipe=()
    [ -t 1 ] || pipe=(--pipe)
    sudo systemd-nspawn -q "${pipe[@]}" -D $M/root \
        --bind=$M/home:/home --bind=$M/boot:/boot --bind=$M/esp:/boot/efi \
        --resolv-conf=replace-uplink --setenv=BOOK4_FROM_ARCH=1 "$@"
}
trap unmounts EXIT
mounts

if [ "${1:-}" = --sync-modules ]; then
    K=${2:-$(cat $M/root/etc/book4/default-kernel)}
    [ -d $M/root/usr/lib/modules/$K/kernel ] || { echo "No modules for $K in Fedora." >&2; exit 1; }
    [ -e $M/boot/vmlinuz-$K ] || { echo "No /boot/vmlinuz-$K." >&2; exit 1; }
    echo "== modules $K: Fedora -> this Arch"
    sudo rm -rf /usr/lib/modules/$K.new
    sudo cp -a $M/root/usr/lib/modules/$K /usr/lib/modules/$K.new
    sudo rm -rf /usr/lib/modules/$K
    sudo mv /usr/lib/modules/$K.new /usr/lib/modules/$K
    sudo depmod $K
    echo "== Arch initramfs"
    T=$(mktemp -d)
    sudo mkinitcpio -k $K -g $T/initramfs.img
    LIST=$(sudo lsinitcpio $T/initramfs.img)   # captured: grep -q in a pipe trips pipefail
    grep -qE '/ufs-qcom\.ko(\.[gx]z|\.zst)?$' <<<"$LIST" ||
        { echo "ufs-qcom.ko missing from the new initramfs, not installing it." >&2; sudo rm -rf $T; exit 1; }
    IMG=$M/boot/initramfs-$K-arch.img
    [ -e $IMG ] && sudo cp -p $IMG $IMG.prev
    sudo install -m 644 $T/initramfs.img $IMG
    sudo rm -rf $T
    echo "== GRUB (Fedora's boot hook, in the container)"
    fedora $HOOK add "$K"
    sudo grep -c cutmem $M/esp/EFI/fedora/grub.cfg
    sudo grep -E '^menuentry' $M/esp/EFI/fedora/grub.cfg
    exit 0
fi

if [ $# -eq 0 ]; then
    echo "Fedora container: your Fedora home, /boot and /boot/efi are Fedora's. exit to leave."
    fedora -u "$USER_NAME" --chdir=/home/$USER_NAME /bin/bash -l
else
    fedora -u "$USER_NAME" --chdir=/home/$USER_NAME "$@"
fi
