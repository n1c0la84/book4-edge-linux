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
#   - its initramfs from /etc/book4/mkinitcpio-omarchy.conf (ours plus
#     Omarchy's Qualcomm platform modules, as stock Omarchy has them; the
#     linux-omarchy preset points there, linux-book4's initramfs is untouched)
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
    sudo rm -f /etc/book4/mkinitcpio-omarchy.conf
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

echo "== 2. initramfs with Omarchy's Qualcomm platform modules"
# Omarchy's kernel builds pin control, interconnect, PMIC and I2C drivers as
# modules; stock Omarchy names them in /etc/mkinitcpio.conf.d/qualcomm-
# platform.conf (install/hardware/qualcomm/initramfs.sh). Without them the
# UFS controller waits forever for its pinctrl and interconnect suppliers and
# the keyboard stays dead (first test, 23 Nov: root device timeout, emergency
# mode). Only this kernel's preset uses the list, so linux-book4's initramfs
# is unchanged: a config of its own (its drop-in directory would be
# <config>.d, which does not exist).
OCONF=/etc/book4/mkinitcpio-omarchy.conf
qsrc=/usr/share/omarchy/install/hardware/qualcomm/initramfs.sh
[ -r "$qsrc" ] || die "no $qsrc (omarchy package)"
{ echo "# install/arch/omarchy-kernel-test.sh: /etc/mkinitcpio.conf + /etc/mkinitcpio.conf.d/*.conf"
  echo "# + Omarchy's Qualcomm platform modules ($qsrc), for linux-omarchy only."
  cat /etc/mkinitcpio.conf
  for f in /etc/mkinitcpio.conf.d/*.conf; do [ -r "$f" ] && { echo "# --- $f"; cat "$f"; }; done
  echo "# --- $qsrc"
  sed -n "/^MODULES+=(/,/)\$/p" "$qsrc"
} > "$w/mkinitcpio-omarchy.conf"
grep -q 'pinctrl-x1e80100' "$w/mkinitcpio-omarchy.conf" || die "could not take the module list from $qsrc"
sudo install -m644 "$w/mkinitcpio-omarchy.conf" "$OCONF"
preset=/etc/mkinitcpio.d/linux-omarchy.preset
sudo sed -i -E "s|^#?default_config=.*|default_config=\"$OCONF\"|" "$preset"
grep -q "^default_config=\"$OCONF\"" "$preset" || die "$preset: default_config not set"
sudo mkinitcpio -p linux-omarchy
list=$(sudo lsinitcpio /boot/initramfs-linux-omarchy.img)   # whole listing: grep -q would cut the pipe
for m in pinctrl-x1e80100 qnoc-x1e80100 ufs-qcom i2c-qcom-geni; do
    grep -q "/$m\.ko" <<<"$list" || die "$m missing from the new initramfs"
done
echo "   pinctrl-x1e80100, qnoc-x1e80100, ufs-qcom, i2c-qcom-geni in the initramfs"

echo "== 3. device trees"
sudo cp "/boot/dtbs/linux-omarchy/qcom/$DTB" "$w/el1.dtb"; sudo chown "$(id -u)" "$w/el1.dtb"
dtc -q -@ -I dts -O dtb -o "$w/el2.dtbo" "$OVERLAY"
fdtoverlay -i "$w/el1.dtb" -o "$w/el2.dtb" "$w/el2.dtbo"
[ "$(fdtget -ts "$w/el2.dtb" /soc@0/gpu@3d00000/zap-shader status)" = disabled ] ||
    die "EL2 DTB: zap shader not disabled, slbounce would not switch"

echo "== 4. UKIs"
CMDLINE=; . /etc/book4/boot.conf
sub=$(findmnt -rn -o FSROOT /); sub=${sub#/}
cmd1="root=UUID=$(findmnt -rn -o UUID /) $CMDLINE rootflags=subvol=$sub"
# The EL1 stock entry boots with Omarchy's own Snapdragon parameters too
# (install/hardware/qualcomm/kernel-params.sh: clk_ignore_unused
# pd_ignore_unused ... iommu.passthrough=0), added where ours lack them.
# Without them its boot stopped at 0.7 s once the platform modules loaded
# (23 Nov); stock Omarchy always has them.
kp=/usr/share/omarchy/install/hardware/qualcomm/kernel-params.sh
cmdel1=$cmd1
for a in $(grep -o '+=" [^"]*"' "$kp" | sed 's/^+=" //; s/"$//'); do
    [[ " $cmdel1 " == *" $a "* ]] || cmdel1="$cmdel1 $a"
done
[[ $cmdel1 == *clk_ignore_unused* ]] || die "could not take Omarchy's kernel parameters from $kp"
echo "   EL1 stock command line: $cmdel1"
sudo cp /boot/vmlinuz-linux-omarchy /boot/initramfs-linux-omarchy.img "$w/"; sudo chown "$(id -u)" "$w"/vmlinuz-* "$w"/initramfs-*
for el in el2 el1; do
    if [ $el = el1 ]; then c=$cmdel1; else c="$cmd1 id_aa64mmfr0.ecv=1"; fi
    ukify build --linux "$w/vmlinuz-linux-omarchy" --initrd "$w/initramfs-linux-omarchy.img" \
        --devicetree "$w/$el.dtb" --cmdline "$c" --stub "$STUB" --uname "$rel" --output "$w/$el.efi" >/dev/null
    sudo install -m644 "$w/$el.efi" "/boot/EFI/Linux/omarchy-kernel-test-$el.efi"
    echo "   /boot/EFI/Linux/omarchy-kernel-test-$el.efi"
done

echo "== 5. Limine entries"
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
    "    cmdline: $cmdel1 $v" |
    sudo tee "$EXTRA" >/dev/null
sudo book4-boot menu
sudo grep '^/' /boot/limine.conf | sed 's/^/   /'
sudo df -h /boot | tail -1
echo "Done. Reboot and pick an 'Omarchy kernel ... (test)' entry in Limine; the default stays linux-book4."
