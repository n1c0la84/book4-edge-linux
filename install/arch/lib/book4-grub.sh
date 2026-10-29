# SPDX-License-Identifier: GPL-2.0-only
# shellcheck shell=bash
# Galaxy Book4 Edge boot chain without Fedora, shared by the live ISO
# (install/arch/live-iso.sh) and its installer (install/arch/book4-install.sh,
# /usr/local/lib/book4/book4-grub.sh on the ISO):
#
#   GRUB (menu) --EL1--> kernel
#               --EL2--> UEFI Shell \EFI\book4-el2\ (startup.nsh: qebspil +
#                        slbounce) -> second GRUB (book4_el2=1) -> kernel
#
# Both GRUB images are grub-mkstandalone with a small built-in config that
# finds the menu's partition ($root) and the ESP ($esp), then loads the menu.

# book4_grub_cfg TITLE KVER DIR ARGS EL2ARGS EL1ARGS
#   DIR: directory (on $root) with vmlinuz, initramfs.img, book4-el1.dtb,
#   book4-el2.dtb; ARGS: root/live arguments; EL2ARGS/EL1ARGS: the rest.
book4_grub_cfg() {
    local title=$1 k=$2 dir=$3 args=$4 el2=$5 el1=$6
    cat <<EOF
# Galaxy Book4 Edge 14" - $title ($(date +%F), kernel $k)
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
  menuentry "$title - EL2 ($k)" {
      devicetree $dir/book4-el2.dtb
      linux  $dir/vmlinuz $args $el2
      initrd $dir/initramfs.img
  }
else
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
fi
EOF
}

# book4_grub_embed ROOT_SEARCH ESP_SEARCH PREFIX [el2]
#   The built-in config: two GRUB commands that set $root and $esp, the
#   menu's directory, and for the second GRUB the EL2 flag.
book4_grub_embed() {
    printf '%s\n%s\nset prefix=%s\n' "$1" "$2" "$3"
    [ "${4:-}" = el2 ] && printf 'set book4_el2=1\nexport book4_el2\n'
    printf 'export esp\nconfigfile $prefix/grub.cfg\n'
}

# GRUB modules preloaded into both images (the rest are in the memdisk).
BOOK4_GRUB_MODULES="part_gpt fat btrfs zstd iso9660 search search_fs_file search_fs_uuid configfile linux fdt mmap efi_gop chain test"
