#!/usr/bin/env bash
# Prepare the "DRIPS + released boot votes" test (16 October):
#  1. rebuild tools/power/icc-hold/icc_hold.ko (Fedora container)
#  2. GRUB test entry "drips-noflags": the DRIPS DTB without
#     clk_ignore_unused pd_ignore_unused
# Then reboot into "test: drips-noflags" and run: bash ~/drips-sync-run.sh
# Run as yourself: bash ~/drips-sync-prep.sh
set -euo pipefail
repo=$HOME/Projects/book4-edge-linux
bash ~/mount-ro.sh off >/dev/null 2>&1 || true   # container and test-entry need sda4/home unmounted
bash "$repo/tools/power/icc-hold/build.sh"
bash "$repo/install/arch/test-entry.sh" add drips-noflags -clk_ignore_unused -pd_ignore_unused dtb=/dtb-test/book4-drips.dtb
bash "$repo/install/arch/test-entry.sh" list
