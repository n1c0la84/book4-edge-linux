#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Boot Omarchy's own kernel (linux-omarchy from Omarchy's edge channel) beside
# linux-book4, from the Limine menu, for birkskyum/arewearmyet#10. Run on Arch
# as your user, in a terminal (sudo asks):
#
#   bash install/arch/omarchy-kernel-test.sh setup         dry run
#   bash install/arch/omarchy-kernel-test.sh setup --yes   install and add the entries
#   bash install/arch/omarchy-kernel-test.sh remove        take it all out again
#
# setup:
#   - pacman -U from https://pkgs.omarchy.org/edge/aarch64 (signed with
#     Omarchy's key, as the [omarchy] repository): linux-omarchy,
#     linux-omarchy-dtbs, systemd-stub-omarchy. The system stays on the stable
#     channel. Arch's mkinitcpio hook writes /boot/vmlinuz-linux-omarchy and
#     /boot/initramfs-linux-omarchy.img (the second ESP, as on stock Omarchy);
#     book4-boot ignores this kernel (no Book4 DTB under /usr/lib/modules).
#   - two UKIs on /boot from Omarchy's own 14" DTB:
#       EFI/Linux/omarchy-kernel-test-el2.efi  DTB + our EL2 overlay (as daily)
#       EFI/Linux/omarchy-kernel-test-el1.efi  the DTB as Omarchy ships it
#     with this system's command line (book4-boot's, ecv=1 at EL2 only)
#   - /etc/book4/limine-extra.conf: two Limine entries, then book4-boot menu
#     (book4-boot appends that file to /boot/limine.conf). Not the default.
# Not installed: edge alsa-ucm-conf (book4-edge owns the same two Samsung UCM
# files) and samsung-galaxy-book4-edge-14-support (its Bluetooth address
# service and keyboard rules would also run on linux-book4, beside ours).
set -euo pipefail
EDGE=https://pkgs.omarchy.org/edge/aarch64
DTB=x1e80100-samsung-galaxy-book4-edge-14.dtb
OVERLAY=/usr/share/book4/x1-el2-book4.dtso
STUB=/usr/lib/systemd/boot/efi/linuxaa64.efi.stub
EXTRA=/etc/book4/limine-extra.conf
PKGS=(linux-omarchy linux-omarchy-dtbs systemd-stub-omarchy)

die() { echo "error: $*" >&2; exit 1; }
[ -e /etc/arch-release ] || die "run this on Arch"
[ "$(id -u)" != 0 ] || die "run as your user (sudo is used inside)"
cmd=${1:-}; yes=; [ "${2:-}" = --yes ] && yes=1

if [ "$cmd" = remove ]; then
    sudo -v
    sudo rm -f /boot/EFI/Linux/omarchy-kernel-test-el1.efi /boot/EFI/Linux/omarchy-kernel-test-el2.efi
    [ ! -e "$EXTRA" ] || sudo rm -f "$EXTRA"
    pacman -Q "${PKGS[@]}" >/dev/null 2>&1 && sudo pacman -R linux-omarchy-dtbs linux-omarchy systemd-stub-omarchy
    sudo book4-boot menu
    echo "Removed. /etc/mkinitcpio.d/linux-omarchy.preset.pacsave may remain (harmless)."
    exit 0
fi
[ "$cmd" = setup ] || { sed -n '3,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 1; }

# --- checks and the current edge files ---------------------------------------
[ "$(findmnt -rn -o LABEL /boot)" = BOOK4ESP ] || die "/boot is not the second ESP (BOOK4ESP)"
sudo -v
sudo test -e /boot/EFI/limine/BOOTAA64.EFI || die "Limine is not set up on /boot (limine-test.sh setup)"
command -v ukify >/dev/null || die "no ukify (pacman -S systemd-ukify)"
[ -e "$OVERLAY" ] || die "no $OVERLAY (book4-edge-boot)"
grep -q LEXTRA /usr/bin/book4-boot || die "book4-boot has no Limine extra entries yet: install the newer book4-edge-boot first"
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
curl -fsS -o "$w/edge.db" "$EDGE/omarchy.db" || die "cannot read the edge repository"
mkdir "$w/db"; tar -xf "$w/edge.db" -C "$w/db"
files=()
for p in "${PKGS[@]}"; do
    d=$(for x in "$w"/db/"$p"-[0-9]*; do [ -d "$x" ] && echo "$x"; done | head -1)
    [ -n "$d" ] || die "$p not in the edge repository"
    files+=("$(awk '/^%FILENAME%$/ { getline; print }' "$d/desc")")
done
avail=$(sudo df --output=avail -m /boot | tail -1)
echo "== plan"
printf '   install from edge: %s\n' "${files[@]}"
echo "   then: two UKIs (EL2 with our overlay, EL1 stock DTB) on /boot/EFI/Linux, entries in $EXTRA, book4-boot menu"
echo "   /boot free: ${avail} MiB (about 350 needed)"
[ "$avail" -ge 400 ] || die "not enough room on /boot"
if [ -z "$yes" ]; then echo; echo "Dry run: nothing changed. Run again with: setup --yes"; exit 0; fi

# --- install -------------------------------------------------------------------
echo "== 1. packages from edge"
sudo pacman -U --needed "${files[@]/#/$EDGE/}"
rel=$(pacman -Ql linux-omarchy | sed -n 's|^linux-omarchy /usr/lib/modules/\([^/]*\)/vmlinuz$|\1|p' | head -1)
[ -n "$rel" ] || die "no linux-omarchy kernel after the install"
for f in /boot/vmlinuz-linux-omarchy /boot/initramfs-linux-omarchy.img "/boot/dtbs/linux-omarchy/qcom/$DTB"; do
    sudo test -e "$f" || die "$f missing after the install"
done

echo "== 2. device trees"
sudo cp "/boot/dtbs/linux-omarchy/qcom/$DTB" "$w/el1.dtb"; sudo chown "$(id -u)" "$w/el1.dtb"
dtc -q -@ -I dts -O dtb -o "$w/el2.dtbo" "$OVERLAY"
fdtoverlay -i "$w/el1.dtb" -o "$w/el2.dtb" "$w/el2.dtbo"
[ "$(fdtget -ts "$w/el2.dtb" /soc@0/gpu@3d00000/zap-shader status)" = disabled ] ||
    die "EL2 DTB: zap shader not disabled, slbounce would not switch"

echo "== 3. UKIs"
CMDLINE=; . /etc/book4/boot.conf
sub=$(findmnt -rn -o FSROOT /); sub=${sub#/}
cmd1="root=UUID=$(findmnt -rn -o UUID /) $CMDLINE rootflags=subvol=$sub"
sudo cp /boot/vmlinuz-linux-omarchy /boot/initramfs-linux-omarchy.img "$w/"; sudo chown "$(id -u)" "$w"/vmlinuz-* "$w"/initramfs-*
for el in el2 el1; do
    c=$cmd1; [ $el = el1 ] || c="$c id_aa64mmfr0.ecv=1"
    ukify build --linux "$w/vmlinuz-linux-omarchy" --initrd "$w/initramfs-linux-omarchy.img" \
        --devicetree "$w/$el.dtb" --cmdline "$c" --stub "$STUB" --uname "$rel" --output "$w/$el.efi" >/dev/null
    sudo install -m644 "$w/$el.efi" "/boot/EFI/Linux/omarchy-kernel-test-$el.efi"
    echo "   /boot/EFI/Linux/omarchy-kernel-test-$el.efi"
done

echo "== 4. Limine entries"
# Verbose variants: the same UKIs with a longer command line (systemd-stub
# takes Limine's cmdline over its own .cmdline without Secure Boot), so a
# boot that stops early prints its kernel messages on screen.
v="earlycon keep_bootcon ignore_loglevel"
printf '%s\n' "# install/arch/omarchy-kernel-test.sh (birkskyum/arewearmyet#10): linux-omarchy $rel" \
    "/Omarchy kernel $rel - EL2 (test)" "    protocol: efi" "    resolution: 1024x768" "    path: boot():/EFI/Linux/omarchy-kernel-test-el2.efi" "" \
    "/Omarchy kernel $rel - EL2, verbose (test)" "    protocol: efi" "    resolution: 1024x768" "    path: boot():/EFI/Linux/omarchy-kernel-test-el2.efi" \
    "    cmdline: $cmd1 id_aa64mmfr0.ecv=1 $v" "" \
    "/Omarchy kernel $rel - EL1, stock DTB (test)" "    protocol: efi" "    resolution: 1024x768" "    path: boot():/EFI/Linux/omarchy-kernel-test-el1.efi" "" \
    "/Omarchy kernel $rel - EL1, stock DTB, verbose (test)" "    protocol: efi" "    resolution: 1024x768" "    path: boot():/EFI/Linux/omarchy-kernel-test-el1.efi" \
    "    cmdline: $cmd1 $v" |
    sudo tee "$EXTRA" >/dev/null
sudo book4-boot menu
sudo grep '^/' /boot/limine.conf | sed 's/^/   /'
sudo df -h /boot | tail -1
echo "Done. Reboot and pick an 'Omarchy kernel ... (test)' entry in Limine; the default stays linux-book4."
