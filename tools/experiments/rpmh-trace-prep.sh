#!/usr/bin/env bash
# GRUB test entry "ufsfix-trace": like "ufsfix" (DRIPS DTB, no clk/pd flags,
# pcie_port_pm=force, patched ufs-qcom initramfs) plus RPMh tracing from boot.
# Then reboot into it and run: bash ~/rpmh-sleepset.sh sync
# Run as yourself: bash ~/rpmh-trace-prep.sh
set -euo pipefail
repo=$HOME/Projects/book4-edge-linux
bash ~/mount-ro.sh off >/dev/null 2>&1 || true
bash "$repo/install/arch/test-entry.sh" remove ufsfix-trace >/dev/null 2>&1 || true
bash "$repo/install/arch/test-entry.sh" add ufsfix-trace -clk_ignore_unused -pd_ignore_unused +pcie_port_pm=force \
  +trace_event=rpmh:rpmh_send_msg +trace_buf_size=8M \
  dtb=/dtb-test/book4-drips.dtb initrd=/initramfs-$(uname -r)-arch-ufstest.img
bash "$repo/install/arch/test-entry.sh" list
