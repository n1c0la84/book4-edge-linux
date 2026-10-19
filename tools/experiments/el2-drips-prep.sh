#!/usr/bin/env bash
# EL2 deep-sleep test prep: install the DRIPS DTB's EL2 variant
# (/boot/dtb-test/book4-drips-el2.dtb) and the GRUB test entry "el2-drips"
# (no clk/pd_ignore_unused, pcie_port_pm=force, id_aa64mmfr0.ecv=1).
# Then: power off, F10, boot the slbounce stick, pick "... - test: el2-drips",
# and run: bash ~/dsp-stop-test.sh
# Run as yourself: bash ~/el2-drips-prep.sh
set -euo pipefail
repo=$HOME/Projects/book4-edge-linux
bash ~/mount-ro.sh off >/dev/null 2>&1 || true
bash "$repo/install/arch/test-entry.sh" remove el2-drips >/dev/null 2>&1 || true
bash "$repo/install/el2/el2-dtb.sh" /dtb-test/book4-drips.dtb el2-drips -clk_ignore_unused -pd_ignore_unused
bash "$repo/install/arch/test-entry.sh" list
