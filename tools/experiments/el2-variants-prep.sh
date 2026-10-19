#!/usr/bin/env bash
# Install the SS1, SS2 and DRIPS-with-power-down-bit DTBs to /boot/dtb-test,
# build their EL2 variants and add three GRUB test entries:
#   "el2-ss1"      system state SS1   0x02000154
#   "el2-ss2"      system state SS2   0x02000254
#   "el2-dripspd"  DRIPS + bit 30     0x4200c354
# (each: no clk/pd_ignore_unused, pcie_port_pm=force, id_aa64mmfr0.ecv=1)
# Then for each: boot the slbounce stick, pick the entry, run ~/el2-probe.sh.
# Run as yourself: bash ~/el2-variants-prep.sh
set -euo pipefail
repo=$HOME/Projects/book4-edge-linux
src=$HOME/src/book4-acpi/dtb
bash ~/mount-ro.sh off >/dev/null 2>&1 || true
findmnt -rn -S /dev/sda4 >/dev/null && { echo "error: /dev/sda4 is mounted" >&2; exit 1; }
sudo -v
m=$(mktemp -d); sudo mount /dev/sda4 "$m"
for v in ss1 ss2 drips-pd; do sudo install -m 644 "$src/book4-$v.dtb" "$m/dtb-test/book4-$v.dtb"; done
ls -la "$m"/dtb-test/book4-{ss1,ss2,drips-pd}.dtb
sudo umount "$m"; rmdir "$m"
for e in "ss1 el2-ss1" "ss2 el2-ss2" "drips-pd el2-dripspd"; do
  set -- $e
  bash "$repo/install/arch/test-entry.sh" remove "$2" >/dev/null 2>&1 || true
  bash "$repo/install/el2/el2-dtb.sh" "/dtb-test/book4-$1.dtb" "$2" -clk_ignore_unused -pd_ignore_unused
done
bash "$repo/install/arch/test-entry.sh" list
