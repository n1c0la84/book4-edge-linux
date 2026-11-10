#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Board power in deep sleep: one device-tree change at a time, each as its
# own GRUB entry "el2-VARIANT" next to the daily "el2-sleep" (which is never
# touched). The sleep log (install/arch/sleep-log.sh) records which entry
# every sleep was on, so normal use compares them; journalctl -t book4-sleep.
#
#   mods    GPIO 44 freed (gpio-reserved-ranges <35 1>, <45 3>) plus the
#           book4-mods sleep hook: low before suspend, high after, as
#           Windows' firmware drives the EC's Modern Standby input (MODS).
#           Result 21-22 October: no saving (~0.9-1.0 W, as el2-sleep).
#   nomisc  VREG_MISC_3P3 without regulator-always-on: the touchscreen's
#           driver (not a wake source) switches its rail off at suspend.
#           The touchpad and keyboard declare no supply; if they share the
#           rail on the board, they lose power in sleep too (the keyboard
#           would then not wake the machine; the lid still does).
#   omshape linux-omarchy's shape (omarchy#15860, asked by its maintainer):
#           clusters without CL5 (as Jens Glathe's cluster_cl5 drop) and
#           no system-level idle state (7.3's hamoa.dtsi has none), so
#           s2idle never asks for SS1 or DRIPS. Same kernel, DC ZVA
#           patches included (harmless: the hang needs CL5).
#   nocl5   clusters without CL5, SS1 and DRIPS kept: does the firmware
#           still enter DRIPS (its PSCI parameter carries CL5's 0x50)?
#           Expect no DRIPS entries, or a failed or hung suspend.
#
# Run on Arch as your user:  bash tools/power/el2-dt-test.sh VARIANT [undo]
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
variant=${1:-}; action=${2:-}
case "$variant" in mods|nomisc|omshape|nocl5) ;; *) sed -n '3,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 1 ;; esac
src=/dtb-test/book4-sleep-el2.dtb
dst=/dtb-test/book4-sleep-el2-$variant.dtb
name=el2-$variant
hook=/usr/lib/systemd/system-sleep/book4-mods
tlmm=/soc@0/pinctrl@f100000
misc=/regulator-misc-3p3

[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
if findmnt -rn -S /dev/sda4 >/dev/null; then echo "error: /dev/sda4 (/boot) is mounted; unmount it first" >&2; exit 1; fi
for t in fdtget fdtput; do command -v $t >/dev/null || { echo "error: $t missing (dtc package)" >&2; exit 1; }; done
sudo -v

if [ "$action" = undo ]; then
    bash "$repo/install/arch/test-entry.sh" remove "$name"
    b=$(mktemp -d); sudo mount /dev/sda4 "$b"; sudo rm -f "$b$dst"; sync; sudo umount "$b"; rmdir "$b"
    [ "$variant" != mods ] || sudo rm -f "$hook"
    echo "Removed the entry '$name' and its DTB."
    exit 0
fi

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
b=$(mktemp -d); sudo mount -o ro /dev/sda4 "$b"
[ -s "$b$src" ] || { sudo umount "$b"; rmdir "$b"; echo "error: no $src; run install/el2/sleep-setup.sh first" >&2; exit 1; }
cp "$b$src" "$work/v.dtb"; sudo umount "$b"
case "$variant" in
mods)
    echo "   gpio-reserved-ranges: $(fdtget -t u "$work/v.dtb" $tlmm gpio-reserved-ranges) -> 35 1 45 3"
    fdtput -t u "$work/v.dtb" $tlmm gpio-reserved-ranges 35 1 45 3 ;;
nomisc)
    [ "$(fdtget "$work/v.dtb" $misc regulator-name)" = VREG_MISC_3P3 ] ||
        { echo "error: $misc is not VREG_MISC_3P3 in $src" >&2; exit 1; }
    fdtput -d "$work/v.dtb" $misc regulator-always-on
    echo "   $misc (VREG_MISC_3P3): regulator-always-on removed" ;;
omshape|nocl5)
    # CL4 by its phandle, checked by PSCI parameter rather than assumed.
    cl4=/cpus/domain-idle-states/cluster-sleep-0
    [ "$(fdtget -t x "$work/v.dtb" $cl4 arm,psci-suspend-param)" = 1000044 ] ||
        { echo "error: $cl4 is not CL4 (0x01000044) in $src" >&2; exit 1; }
    ph=$(fdtget -t u "$work/v.dtb" $cl4 phandle)
    for c in 0 1 2; do
        pd=/psci/power-domain-cpu-cluster$c
        echo "   $pd: domain-idle-states $(fdtget -t x "$work/v.dtb" $pd domain-idle-states) -> $(printf %x "$ph") (CL4 only)"
        fdtput -t u "$work/v.dtb" $pd domain-idle-states "$ph"
    done
    if [ "$variant" = omshape ]; then
        fdtput -d "$work/v.dtb" /psci/power-domain-system domain-idle-states
        echo "   /psci/power-domain-system: domain-idle-states removed (no SS1, no DRIPS)"
    fi ;;
esac
sudo mount /dev/sda4 "$b"
sudo install -m 644 "$work/v.dtb" "$b$dst"; sync
sudo umount "$b"; rmdir "$b"

# The daily entry with only the DTB changed (as install/el2/el2-dtb.sh adds it).
bash "$repo/install/arch/test-entry.sh" remove "$name" >/dev/null 2>&1 || true
bash "$repo/install/arch/test-entry.sh" add "$name" +id_aa64mmfr0.ecv=1 -clk_ignore_unused -pd_ignore_unused \
    kernel=/vmlinuz-7.2.7-book4s initrd=/initramfs-7.2.7-book4s-arch.img "dtb=$dst"
[ "$variant" != mods ] || sudo install -m 755 "$repo/userspace/standby/book4-mods" "$hook"
echo
echo "Pick '... - test: $name' in GRUB when you want it; its sleeps are logged as"
echo "'$name' (journalctl -t book4-sleep). Re-run this after install/el2/sleep-setup.sh."
