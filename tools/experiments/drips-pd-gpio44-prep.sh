#!/usr/bin/env bash
# EL1 entry "drips-pd-mods": the DRIPS-with-power-down-bit DTB with GPIO 44
# (EC "standby" input MODS) no longer reserved (gpio-reserved-ranges <35 1>,
# <45 3> instead of <35 1>, <44 4>; booted fine with 44 free on 3 October).
# Then: reboot into "test: drips-pd-mods" and run: bash ~/el2-probe.sh mods noqsee
# Run as yourself: bash ~/drips-pd-gpio44-prep.sh
set -euo pipefail
te=$HOME/Projects/book4-edge-linux/install/arch/test-entry.sh
bash ~/mount-ro.sh off >/dev/null 2>&1 || true
findmnt -rn -S /dev/sda4 >/dev/null && { echo "error: /dev/sda4 is mounted" >&2; exit 1; }
sudo -v
m=$(mktemp -d); sudo mount /dev/sda4 "$m"
sudo install -m 644 ~/src/book4-acpi/dtb/book4-drips-pd-gpio44.dtb "$m/dtb-test/book4-drips-pd-gpio44.dtb"
sudo umount "$m"; rmdir "$m"
bash "$te" remove drips-pd-mods >/dev/null 2>&1 || true
bash "$te" add drips-pd-mods -clk_ignore_unused -pd_ignore_unused dtb=/dtb-test/book4-drips-pd-gpio44.dtb
bash "$te" list | grep -E '^menuentry'
