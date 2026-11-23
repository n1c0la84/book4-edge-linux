#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# docs/plan-limine.md step 3: Limine by hand, beside Arch GRUB, from a
# firmware entry of its own that is NOT in the boot order. Run on Arch as
# your user, in a terminal (sudo asks):
#
#   bash install/arch/limine-test.sh setup         dry run: what it would write
#   bash install/arch/limine-test.sh setup --yes   write it
#   bash install/arch/limine-test.sh next          boot Limine once (BootNext), then reboot yourself
#   bash install/arch/limine-test.sh status
#
# setup:
#   - pacman -S --needed limine systemd-ukify
#   - second ESP (/boot, BOOK4ESP): \EFI\limine\BOOTAA64.EFI, \limine.conf,
#     /book4/<rel>/ (vmlinuz, initramfs.img, el2.dtb, el1.dtb copied from
#     sda4, as book4-boot made them), \EFI\Linux\book4-<rel>-el2.efi (a UKI
#     with only our EL2 DTB, so systemd-stub installs that DTB in the EFI
#     configuration table, where slbounce and qebspil look at
#     ExitBootServices)
#   - firmware ESP (sda1): new folder \EFI\book4-el2-limine\ (UEFI Shell copy
#     + install/limine/startup.nsh: qebspil, slbounce, then Limine; Arch GRUB
#     if Limine is missing or returns). Nothing else on sda1 changes.
#   - firmware entry "Omarchy (EL2, Limine)", created with --create-only
#     (BootOrder unchanged)
# Menu entries: 1 EL2 UKI (efi protocol), 2 EL2 kernel + dtb_path (linux
# protocol), 3 EL1 kernel + dtb_path, 4 Arch GRUB. Command line: exactly the
# one book4-boot gives the default GRUB entry. No cutmem (Limine has none):
# testing whether 7.3 still needs it is part of this step.
# Since book4-edge-boot with the Limine side (plan step 4), book4-boot keeps
# the kernel files, UKIs and limine.conf current; setup stays the way to make
# the firmware entry and the Shell folder on a fresh install.
# Undo: efibootmgr -b XXXX -B (the entry); remove /boot/EFI/limine,
# /boot/limine.conf, /boot/book4, /boot/EFI/Linux; \EFI\book4-el2-limine\ on
# sda1 may stay.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$here/../.." && pwd)
LABEL="Omarchy (EL2, Limine)"
LOADER='\EFI\book4-el2-limine\Shellaa64.efi'
SHELLARGS="Shellaa64.efi -delay 0"
SDA4=/dev/sda4
STUB=/usr/lib/systemd/boot/efi/linuxaa64.efi.stub
DTB=x1e80100-samsung-galaxy-book4-edge-14.dtb

die() { echo "error: $*" >&2; exit 1; }
[ -e /etc/arch-release ] || die "run this on Arch"
[ "$(id -u)" != 0 ] || die "run as your user (sudo is used inside)"

entry() {  # Boot#### of our loader path
    # Through the environment: awk -v would treat the backslashes as escapes.
    efibootmgr | L=$(tr 'A-Z' 'a-z' <<<")/$LOADER") awk '
        BEGIN { l = ENVIRON["L"] }
        /^Boot[0-9A-F][0-9A-F][0-9A-F][0-9A-F]/ { if (!f && index(tolower($0), l)) { print substr($0, 5, 4); f = 1 } }'
}

cmd=${1:-}; yes=; [ "${2:-}" = --yes ] && yes=1
case "$cmd" in
status)
    n=$(entry)
    echo "firmware entry: ${n:+Boot$n }$([ -n "$n" ] || echo none)"
    efibootmgr | grep -E '^Boot(Current|Next|Order)'
    sudo ls -la /boot /boot/EFI/limine /boot/EFI/Linux 2>/dev/null || true
    sudo cat /boot/limine.conf 2>/dev/null | grep -E '^/|path|cmdline' || true
    exit 0 ;;
next)
    n=$(entry); [ -n "$n" ] || die "no \"$LABEL\" firmware entry; run setup --yes first"
    sudo efibootmgr -q -n "$n"
    efibootmgr | grep -E '^Boot(Next|Order)'
    echo "Next boot (once): Boot$n \"$LABEL\". Reboot when ready; the boot after it is back to the normal order."
    exit 0 ;;
setup) ;;
*) sed -n '3,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 1 ;;
esac

# --- checks -----------------------------------------------------------------
[ "$(findmnt -rn -o LABEL /boot)" = BOOK4ESP ] || die "/boot is not the second ESP (BOOK4ESP); see boot-split.sh"
ls /efi/ >/dev/null 2>&1 || true
ESP=$(findmnt -rn -o TARGET -S /dev/sda1 | head -1) || true
[ -n "$ESP" ] || die "the firmware ESP (sda1) is not mounted at /efi"
! findmnt -rn -S $SDA4 >/dev/null || die "$SDA4 is mounted; unmount it first"
sudo -v
rel=$(pacman -Ql linux-book4 | sed -n 's|^linux-book4 /usr/lib/modules/\([^/]*\)/vmlinuz$|\1|p' | head -1)
[ -n "$rel" ] || die "no linux-book4 kernel"
# The default GRUB entry's command line, as book4-boot writes it.
# Read the whole menu first: awk exiting early would break book4-boot's pipe.
menu=$(sudo book4-boot menu --print)
line=$(awk '/--id book4-default \{/ { on = 1 } on && /^[[:space:]]*linux[[:space:]]/ { print; exit }' <<<"$menu")
cmdline=$(sed -E 's/^[[:space:]]*linux[[:space:]]+\S+[[:space:]]+//' <<<"$line")
[[ $cmdline == *root=UUID=* && $cmdline == *rootflags=subvol=* ]] || die "could not read the default entry's command line: $line"
el1cmd=${cmdline/ id_aa64mmfr0.ecv=1/}
shell_src=$ESP/EFI/book4-el2-arch/Shellaa64.efi
sudo test -e "$shell_src" || die "no $shell_src (book4-el2 install)"
espguid=$(lsblk -no PARTUUID /dev/sda1)
# A stale package database names files the mirror no longer has.
for u in $(pacman -Sp --needed limine systemd-ukify 2>/dev/null | grep -E '^(https?|ftp)://'); do
    curl -sfI -o /dev/null "$u" || die "the mirror no longer has ${u##*/}: run book4-update first (pacman -Syu)"
done

conf=$(cat <<EOF
# Galaxy Book4 Edge: Limine on the second ESP (BOOK4ESP). Written by
# install/arch/limine-test.sh (book4-edge-linux); started by the UEFI Shell in
# \\EFI\\book4-el2-limine\\ on sda1 after qebspil and slbounce.
timeout: 10
default_entry: 1
interface_branding: Omarchy Bootloader (Book4 test)
interface_branding_color: 9ece6a
term_background: 1a1b26
backdrop: 1a1b26
term_foreground: c0caf5

/Omarchy ($rel) - EL2, UKI
    protocol: efi
    path: boot():/EFI/Linux/book4-$rel-el2.efi

/Omarchy ($rel) - EL2, kernel + DTB
    protocol: linux
    path: boot():/book4/$rel/vmlinuz
    module_path: boot():/book4/$rel/initramfs.img
    dtb_path: boot():/book4/$rel/el2.dtb
    cmdline: $cmdline

/Omarchy ($rel) - EL1, kernel + DTB
    protocol: linux
    path: boot():/book4/$rel/vmlinuz
    module_path: boot():/book4/$rel/initramfs.img
    dtb_path: boot():/book4/$rel/el1.dtb
    cmdline: $el1cmd

/Arch GRUB
    protocol: efi
    path: guid($espguid):/EFI/arch/grubaa64.efi
EOF
)

echo "== plan"
echo "   kernel $rel; command line (EL2): $cmdline"
echo "   packages: limine systemd-ukify (--needed)"
echo "   /boot (sda7): EFI/limine/BOOTAA64.EFI, limine.conf, book4/$rel/{vmlinuz,initramfs.img,el2.dtb,el1.dtb}, EFI/Linux/book4-$rel-el2.efi"
echo "   $ESP (sda1): EFI/book4-el2-limine/{Shellaa64.efi,startup.nsh}"
n=$(entry)
echo "   firmware entry: $([ -n "$n" ] && echo "Boot$n present" || echo "\"$LABEL\" -> $LOADER, not in BootOrder")"
echo "== limine.conf"; sed 's/^/   /' <<<"$conf"
if [ -z "$yes" ]; then echo; echo "Dry run: nothing changed. Run again with: setup --yes"; exit 0; fi

echo "== 1. packages"
sudo pacman -S --needed limine systemd-ukify
[ -e "$STUB" ] || die "no $STUB"

echo "== 2. kernel set from sda4"
w=$(mktemp -d); b=$(mktemp -d)
cleanup() { sudo umount "$b" 2>/dev/null || true; rmdir "$b"; rm -rf "$w"; }
trap cleanup EXIT
sudo mount -o ro $SDA4 "$b"
sudo install -d /boot/book4/$rel /boot/EFI/limine /boot/EFI/Linux
sudo install -m644 "$b/vmlinuz-$rel" /boot/book4/$rel/vmlinuz
sudo install -m644 "$b/initramfs-$rel-arch.img" /boot/book4/$rel/initramfs.img
sudo install -m644 "$b/dtb-$rel/${DTB%.dtb}-el2.dtb" /boot/book4/$rel/el2.dtb
sudo install -m644 "$b/dtb-$rel/$DTB" /boot/book4/$rel/el1.dtb
[ "$(fdtget -ts /boot/book4/$rel/el2.dtb /soc@0/gpu@3d00000/zap-shader status 2>/dev/null || sudo fdtget -ts /boot/book4/$rel/el2.dtb /soc@0/gpu@3d00000/zap-shader status)" = disabled ] ||
    die "el2.dtb: zap shader not disabled"

echo "== 3. UKI (EL2 DTB only)"
sudo cp /boot/book4/$rel/{vmlinuz,initramfs.img,el2.dtb} "$w/"; sudo chown "$(id -u)" "$w"/*
ukify build --linux "$w/vmlinuz" --initrd "$w/initramfs.img" --devicetree "$w/el2.dtb" \
    --cmdline "$cmdline" --stub "$STUB" --uname "$rel" --output "$w/uki.efi"
sudo install -m644 "$w/uki.efi" /boot/EFI/Linux/book4-$rel-el2.efi

echo "== 4. Limine"
sudo install -m644 /usr/share/limine/BOOTAA64.EFI /boot/EFI/limine/BOOTAA64.EFI
[ ! -e /boot/limine.conf ] || sudo cp /boot/limine.conf /boot/limine.conf.old
printf '%s\n' "$conf" | sudo tee /boot/limine.conf >/dev/null

echo "== 5. UEFI Shell folder on sda1"
sudo install -d "$ESP/EFI/book4-el2-limine"
sudo install -m644 "$shell_src" "$ESP/EFI/book4-el2-limine/Shellaa64.efi"
sudo install -m644 "$REPO/install/limine/startup.nsh" "$ESP/EFI/book4-el2-limine/startup.nsh"
sync

echo "== 6. firmware entry (not in BootOrder)"
if [ -z "$(entry)" ]; then
    before=$(efibootmgr | sed -n 's/^BootOrder: //p')
    sudo efibootmgr -q --create-only --disk /dev/sda --part 1 --label "$LABEL" --loader "$LOADER" --unicode "$SHELLARGS"
    after=$(efibootmgr | sed -n 's/^BootOrder: //p')
    [ "$before" = "$after" ] || { sudo efibootmgr -q -o "$before"; echo "   BootOrder restored to $before"; }
fi
n=$(entry); [ -n "$n" ] || die "firmware entry not created"
efibootmgr | grep -E "^Boot($n|Order)"
df -h /boot | tail -1
echo "Done. To test: bash install/arch/limine-test.sh next, then reboot."
