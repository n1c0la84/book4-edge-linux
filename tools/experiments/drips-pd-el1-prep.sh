#!/usr/bin/env bash
# EL1 entry for the DRIPS-with-power-down-bit DTB (book4-drips-pd.dtb,
# 0x4200c354, already in /boot/dtb-test from el2-variants-prep.sh):
# GRUB test entry "drips-pd", no clk/pd_ignore_unused (pcie_port_pm=force is
# in the default command line already).
# Run as yourself: bash ~/drips-pd-el1-prep.sh
set -euo pipefail
te=$HOME/Projects/book4-edge-linux/install/arch/test-entry.sh
bash ~/mount-ro.sh off >/dev/null 2>&1 || true
bash "$te" remove drips-pd >/dev/null 2>&1 || true
bash "$te" add drips-pd -clk_ignore_unused -pd_ignore_unused dtb=/dtb-test/book4-drips-pd.dtb
bash "$te" list | grep -E '^menuentry'
