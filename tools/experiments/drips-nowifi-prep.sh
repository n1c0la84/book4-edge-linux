#!/usr/bin/env bash
# Prepare the maximal DRIPS test: DRIPS DTB with the Wi-Fi PCIe controller
# (pci@1c08000) and its PHY disabled, no clk/pd_ignore_unused.
# GRUB test entry "drips-nowifi". No Wi-Fi on that boot (Bluetooth stays).
# Then reboot into "test: drips-nowifi" and run: bash ~/drips-sync-run.sh nowifi
# Run as yourself: bash ~/drips-nowifi-prep.sh
set -euo pipefail
dtb=$HOME/src/book4-acpi/dtb/book4-drips-nowifi.dtb
repo=$HOME/Projects/book4-edge-linux
bash ~/mount-ro.sh off >/dev/null 2>&1 || true
findmnt -rn -S /dev/sda4 >/dev/null && { echo "error: /dev/sda4 is mounted; unmount it first" >&2; exit 1; }
m=$(mktemp -d)
sudo mount /dev/sda4 "$m"
sudo install -m 644 "$dtb" "$m/dtb-test/book4-drips-nowifi.dtb"
ls -la "$m/dtb-test/"
sudo umount "$m"; rmdir "$m"
bash "$repo/install/arch/test-entry.sh" add drips-nowifi -clk_ignore_unused -pd_ignore_unused dtb=/dtb-test/book4-drips-nowifi.dtb
bash "$repo/install/arch/test-entry.sh" list
