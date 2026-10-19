#!/usr/bin/env bash
# GRUB test entry "el2-pdc": the 7.3 PDC backport kernel at EL2 (slbounce),
# EL2 variant of /dtb-test/book4-pdc.dtb (upstream domain_ss3 in the OSI
# hierarchy). Run on the normal boot, as yourself: bash ~/el2-pdc-prep.sh
# Then: slbounce stick, pick "test: el2-pdc", run: bash ~/el2-pdc-test.sh
set -euo pipefail
repo=$HOME/Projects/book4-edge-linux
bash ~/mount-ro.sh off >/dev/null 2>&1 || true
bash "$repo/install/arch/test-entry.sh" remove el2-pdc >/dev/null 2>&1 || true
bash "$repo/install/el2/el2-dtb.sh" /dtb-test/book4-pdc.dtb el2-pdc \
    -clk_ignore_unused -pd_ignore_unused kernel=/vmlinuz-7.2.7-book4-pdc
