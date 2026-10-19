#!/usr/bin/env bash
# The x1e-sleep recipe on the Book4: the sleep test kernel 7.2.7-book4s at
# EL2 (slbounce) with el1tmr. Builds the out-of-tree modules (el1tmr is new),
# then the EL2 variant of /dtb-test/book4-sleep.dtb and GRUB entry
# "el2-sleep". Run on a normal (non-EL2) Arch boot, as yourself:
#   bash ~/el2-sleep-prep.sh
# Then: slbounce stick, pick "test: el2-sleep", run: bash ~/el2-sleep-test.sh
set -euo pipefail
repo=$HOME/Projects/book4-edge-linux
bash ~/mount-ro.sh off >/dev/null 2>&1 || true
bash "$repo/tools/kernel/build-sleep-modules.sh"
bash "$repo/install/arch/test-entry.sh" remove el2-sleep >/dev/null 2>&1 || true
bash "$repo/install/el2/el2-dtb.sh" /dtb-test/book4-sleep.dtb el2-sleep -clk_ignore_unused -pd_ignore_unused \
    kernel=/vmlinuz-7.2.7-book4s initrd=/initramfs-7.2.7-book4s-arch.img
