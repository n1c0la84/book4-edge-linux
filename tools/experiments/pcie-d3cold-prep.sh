#!/usr/bin/env bash
# GRUB test entry "drips-pcie": DRIPS DTB, no clk/pd_ignore_unused, plus
# pcie_port_pm=force so the Wi-Fi root port may enter D3hot in suspend; then
# the kernel's own D3cold path (dw_pcie_suspend_noirq) powers the PCIe
# controller off and re-inits it on resume, no remove/rescan needed.
# Run as yourself: bash ~/pcie-d3cold-prep.sh
set -euo pipefail
repo=$HOME/Projects/book4-edge-linux
bash ~/mount-ro.sh off >/dev/null 2>&1 || true
bash "$repo/install/arch/test-entry.sh" add drips-pcie -clk_ignore_unused -pd_ignore_unused +pcie_port_pm=force dtb=/dtb-test/book4-drips.dtb
bash "$repo/install/arch/test-entry.sh" list
