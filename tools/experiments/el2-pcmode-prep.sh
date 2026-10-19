#!/usr/bin/env bash
# PSCI platform-coordinated (PC) mode at EL2, as under Windows/Hyper-V (which
# never switch TrustZone to OS-initiated mode). Two DTBs without the PSCI
# power-domain hierarchy, flat CPU idle states C4 / CL5 / DRIPS:
#   "el2-pc"    cluster 0x01000054, system 0x0200c354
#   "el2-pcpd"  same with the power-down bit: 0x41000054, 0x4200c354
# Then: boot the slbounce stick, pick one, run: bash ~/el2-probe.sh
# Run as yourself: bash ~/el2-pcmode-prep.sh
set -euo pipefail
repo=$HOME/Projects/book4-edge-linux
src=$HOME/src/book4-acpi/pcmode
bash ~/mount-ro.sh off >/dev/null 2>&1 || true
findmnt -rn -S /dev/sda4 >/dev/null && { echo "error: /dev/sda4 is mounted" >&2; exit 1; }
sudo -v
m=$(mktemp -d); sudo mount /dev/sda4 "$m"
for v in pcmode pcmode-pd; do sudo install -m 644 "$src/book4-$v.dtb" "$m/dtb-test/book4-$v.dtb"; done
sudo umount "$m"; rmdir "$m"
for e in "pcmode el2-pc" "pcmode-pd el2-pcpd"; do
  set -- $e
  bash "$repo/install/arch/test-entry.sh" remove "$2" >/dev/null 2>&1 || true
  bash "$repo/install/el2/el2-dtb.sh" "/dtb-test/book4-$1.dtb" "$2" -clk_ignore_unused -pd_ignore_unused
done
bash "$repo/install/arch/test-entry.sh" list | grep -E '^menuentry'
