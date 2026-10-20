#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Board power in deep sleep: does telling the EC "Modern Standby" save power?
# Windows' firmware pulls TLMM GPIO 44 (MODS, the EC's standby input) low at
# Modern Standby "display off" and high at "display on" (DSDT, docs/power.md
# "What Windows does at Modern Standby"). Linux never does: the device tree
# reserves GPIOs 44-47. On 3 October, driving it changed the EC's behaviour
# in sleep (charge LED off); what it does to power was never measured.
#
# Sets up, without touching the daily entry:
#   /boot/dtb-test/book4-sleep-el2-mods.dtb  the daily EL2 DTB with GPIO 44
#        freed (gpio-reserved-ranges <35 1>, <45 3>)
#   GRUB test entry "el2-mods"               the daily entry with that DTB
#   /usr/lib/systemd/system-sleep/book4-mods  the hook from userspace/standby:
#        GPIO 44 low before suspend, high after; does nothing on boots where
#        GPIO 44 is still reserved, i.e. every other entry
#
# Then: reboot into "el2-mods" (GRUB menu), run tools/power/el2-drain-test.sh
# for 70-90 min on battery, and compare the watts with a daily-entry run of
# the same length. journalctl -t book4-mods shows the hook acting.
#
# Run on Arch as your user:  bash tools/power/el2-mods-test.sh [undo]
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
src=/dtb-test/book4-sleep-el2.dtb
dst=/dtb-test/book4-sleep-el2-mods.dtb
hook=/usr/lib/systemd/system-sleep/book4-mods
name=el2-mods
tlmm=/soc@0/pinctrl@f100000

[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
if findmnt -rn -S /dev/sda4 >/dev/null; then echo "error: /dev/sda4 (/boot) is mounted; unmount it first" >&2; exit 1; fi
for t in fdtget fdtput; do command -v $t >/dev/null || { echo "error: $t missing (dtc package)" >&2; exit 1; }; done
sudo -v

if [ "${1:-}" = undo ]; then
    bash "$repo/install/arch/test-entry.sh" remove "$name"
    b=$(mktemp -d); sudo mount /dev/sda4 "$b"; sudo rm -f "$b$dst"; sync; sudo umount "$b"; rmdir "$b"
    sudo rm -f "$hook"
    echo "Removed the entry, the DTB and the hook."
    exit 0
fi

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
b=$(mktemp -d); sudo mount -o ro /dev/sda4 "$b"
[ -s "$b$src" ] || { sudo umount "$b"; rmdir "$b"; echo "error: no $src; run install/el2/sleep-setup.sh first" >&2; exit 1; }
cp "$b$src" "$work/mods.dtb"; sudo umount "$b"
echo "   $src: gpio-reserved-ranges = $(fdtget -t u "$work/mods.dtb" $tlmm gpio-reserved-ranges)"
fdtput -t u "$work/mods.dtb" $tlmm gpio-reserved-ranges 35 1 45 3
echo "   $dst: gpio-reserved-ranges = $(fdtget -t u "$work/mods.dtb" $tlmm gpio-reserved-ranges)"
sudo mount /dev/sda4 "$b"
sudo install -m 644 "$work/mods.dtb" "$b$dst"; sync
sudo umount "$b"; rmdir "$b"

# The daily entry with only the DTB changed (as install/el2/el2-dtb.sh adds it).
bash "$repo/install/arch/test-entry.sh" remove "$name" >/dev/null 2>&1 || true
bash "$repo/install/arch/test-entry.sh" add "$name" +id_aa64mmfr0.ecv=1 -clk_ignore_unused -pd_ignore_unused \
    kernel=/vmlinuz-7.2.7-book4s initrd=/initramfs-7.2.7-book4s-arch.img "dtb=$dst"

sudo install -m 755 "$repo/userspace/standby/book4-mods" "$hook"
echo
echo "Reboot, pick '... - test: $name' in GRUB, then (on battery):"
echo "  bash tools/power/el2-drain-test.sh     # wake after 70-90 min"
echo "  journalctl -b -t book4-mods            # 'GPIO 44 = 0 (pre ...)' / '= 1 (post ...)'"
