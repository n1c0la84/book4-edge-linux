# SPDX-License-Identifier: GPL-2.0-only
# shellcheck shell=bash
# Galaxy Book4 Edge boot chain without Fedora, shared by the live ISO
# (install/arch/live-iso.sh) and its installer (install/arch/book4-install.sh,
# /usr/local/lib/book4/book4-grub.sh on the ISO):
#
#   GRUB (menu, grub.cfg) --EL1--> kernel
#                         --EL2--> UEFI Shell \EFI\book4-el2\ (startup.nsh:
#                                  qebspil + slbounce) -> second GRUB
#                                  (grub-el2.cfg, EL2 entries only) -> kernel
#
# Both GRUB images are grub-mkstandalone with a small built-in config that
# finds the menu's partition ($root) and the ESP ($esp), then loads its own
# menu file. The second GRUB used to load the same grub.cfg with an exported
# flag (book4_el2=1) choosing the EL2 entry; on the live stick (4 November
# 2026) the flag did not take effect and the full menu came back after
# slbounce, looping GRUB -> Shell -> GRUB without a reset.

# book4_grub_head TITLE KVER: comment, gfxpayload and the cutmem workaround,
# at the top of both menu files.
book4_grub_head() {
    cat <<EOF
# Galaxy Book4 Edge 14" - $1 ($(date +%F), kernel $2)
set gfxpayload=keep
# Snapdragon X firmware memory-map workaround; without it this machine resets.
if [ "\$lockdown" != "y" ]; then
  cutmem 0x8800000000 0x8fffffffff
fi
EOF
}

# book4_grub_cfg TITLE KVER DIR ARGS EL2ARGS EL1ARGS -> grub.cfg (first GRUB)
#   DIR: directory (on $root) with vmlinuz, initramfs.img, book4-el1.dtb,
#   book4-el2.dtb; ARGS: root/live arguments; EL2ARGS/EL1ARGS: the rest
#   (EL2ARGS unused here; same arguments as book4_grub_el2_cfg).
book4_grub_cfg() {
    local title=$1 k=$2 dir=$3 args=$4 el1=$6
    book4_grub_head "$title" "$k"
    cat <<EOF
set timeout=5
set timeout_style=menu

menuentry "$title - EL2 (deep sleep; via UEFI Shell + slbounce)" {
    chainloader (\$esp)/EFI/book4-el2/Shellaa64.efi
}
menuentry "$title - EL1 (no deep sleep)" {
    devicetree $dir/book4-el1.dtb
    linux  $dir/vmlinuz $args $el1
    initrd $dir/initramfs.img
}
menuentry "$title - EL1, verbose" {
    devicetree $dir/book4-el1.dtb
    linux  $dir/vmlinuz $args $el1 earlycon keep_bootcon ignore_loglevel
    initrd $dir/initramfs.img
}
menuentry "UEFI Firmware Settings" { fwsetup }
EOF
}

# book4_grub_el2_cfg TITLE KVER DIR ARGS EL2ARGS [EL1ARGS] -> grub-el2.cfg
#   The second GRUB's menu, after the UEFI Shell loaded qebspil and slbounce:
#   EL2 entries only, so nothing here can chain the Shell again.
book4_grub_el2_cfg() {
    local title=$1 k=$2 dir=$3 args=$4 el2=$5
    book4_grub_head "$title, EL2" "$k"
    cat <<EOF
set timeout=1
set timeout_style=menu

menuentry "$title - EL2 ($k)" {
    devicetree $dir/book4-el2.dtb
    linux  $dir/vmlinuz $args $el2
    initrd $dir/initramfs.img
}
menuentry "$title - EL2, verbose" {
    devicetree $dir/book4-el2.dtb
    linux  $dir/vmlinuz $args $el2 earlycon keep_bootcon ignore_loglevel
    initrd $dir/initramfs.img
}
EOF
}

# book4_grub_embed ROOT_SEARCH ESP_SEARCH PREFIX [el2]
#   The built-in config: two GRUB commands that set $root and $esp, the menu
#   files' directory, then grub.cfg, or grub-el2.cfg with "el2".
book4_grub_embed() {
    local menu=grub.cfg
    [ "${4:-}" != el2 ] || menu=grub-el2.cfg
    printf '%s\n%s\nset prefix=%s\nexport esp\nconfigfile $prefix/%s\n' "$1" "$2" "$3" "$menu"
}

# GRUB modules preloaded into both images (the rest are in the memdisk).
BOOK4_GRUB_MODULES="part_gpt fat btrfs zstd iso9660 search search_fs_file search_fs_uuid configfile linux fdt mmap efi_gop chain test"
