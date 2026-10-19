#!/usr/bin/env bash
# Install the DRIPS test DTB and a GRUB test entry for it ("test: drips").
# The DTB is the current default (book4-default-1010) plus Windows' DRIPS
# system idle state (PSCI 0x0200C354, from the DSDT's \_SB.SYSM._LPI) on
# psci/power-domain-system, which has no idle state today.
# Default entry and Fedora are untouched; remove with:
#   bash ~/Projects/book4-edge-linux/install/arch/test-entry.sh remove drips
# Run as yourself: bash ~/drips-test.sh
set -euo pipefail
dtb=$HOME/src/book4-acpi/dtb/book4-drips.dtb
repo=$HOME/Projects/book4-edge-linux

findmnt -rn -S /dev/sda4 >/dev/null && { echo "error: /dev/sda4 is mounted; unmount it first" >&2; exit 1; }
m=$(mktemp -d)
sudo mount /dev/sda4 "$m"
sudo mkdir -p "$m/dtb-test"
sudo install -m 644 "$dtb" "$m/dtb-test/book4-drips.dtb"
ls -la "$m/dtb-test/book4-drips.dtb"
sudo umount "$m"; rmdir "$m"

bash "$repo/install/arch/test-entry.sh" add drips dtb=/dtb-test/book4-drips.dtb
bash "$repo/install/arch/test-entry.sh" list
