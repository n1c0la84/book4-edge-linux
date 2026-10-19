#!/usr/bin/env bash
# Re-add the GRUB test entry "el2-drips": EL2, PSCI OSI hierarchy, DRIPS
# 0x0200c354 (no power-down bit) on the system domain. The DTB
# (/boot/dtb-test/book4-drips-el2.dtb) is still there from 17 October.
# Then: boot the slbounce stick, pick "test: el2-drips", run: bash ~/el2-probe.sh
# Run as yourself: bash ~/el2-drips-readd.sh
set -euo pipefail
te=$HOME/Projects/book4-edge-linux/install/arch/test-entry.sh
bash ~/mount-ro.sh off >/dev/null 2>&1 || true
bash "$te" remove el2-drips >/dev/null 2>&1 || true
bash "$te" add el2-drips +id_aa64mmfr0.ecv=1 -clk_ignore_unused -pd_ignore_unused dtb=/dtb-test/book4-drips-el2.dtb
bash "$te" list | grep -E '^menuentry'
