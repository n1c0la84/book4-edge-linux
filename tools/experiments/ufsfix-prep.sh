#!/usr/bin/env bash
# Prepare the UFS ref_clk leak fix test (16 October):
#  1. build ufs-qcom.ko with tools/power/ufs-qcom-lane-clks-guard.patch
#     (Fedora container; asks for the Fedora password)
#  2. a test initramfs carrying it (/boot/initramfs-KVER-arch-ufstest.img)
#  3. GRUB test entry "ufsfix": DRIPS DTB, no clk/pd_ignore_unused,
#     pcie_port_pm=force, that initramfs
# Then reboot into "test: ufsfix" and run:  bash ~/drips-sync-run.sh full
# Run as yourself: bash ~/ufsfix-prep.sh
set -euo pipefail
repo=$HOME/Projects/book4-edge-linux
p=$repo/tools/power
bash ~/mount-ro.sh off >/dev/null 2>&1 || true
bash "$p/build-ufs-patch.sh" "$p/ufs-qcom-lane-clks-guard.patch"
bash "$p/make-ufstest-initramfs.sh"
bash "$repo/install/arch/test-entry.sh" remove ufsfix >/dev/null 2>&1 || true
bash "$repo/install/arch/test-entry.sh" add ufsfix -clk_ignore_unused -pd_ignore_unused +pcie_port_pm=force \
  dtb=/dtb-test/book4-drips.dtb initrd=/initramfs-$(uname -r)-arch-ufstest.img
bash "$repo/install/arch/test-entry.sh" list
