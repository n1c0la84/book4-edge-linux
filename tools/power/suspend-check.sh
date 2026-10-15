#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Quick suspend/resume check of the storage (UFS): every driver suspends and
# resumes with pm_test=devices (no real sleep, back after ~5 s), then a
# direct (uncached) write+read on the root filesystem, and the kernel's
# storage messages. Everything needed afterwards is loaded into memory
# first, so if the disk is lost the result still appears: photograph the
# screen, then hold the power button.
#
#   bash tools/power/suspend-check.sh
set -uo pipefail
f=$HOME/.suspend-check.bin
sudo -v || exit 1
sudo dmesg >/dev/null; dd --version >/dev/null; grep --version >/dev/null; tail --version >/dev/null; date >/dev/null
sudo sh -c 'cat /sys/power/pm_test >/dev/null'
mark="suspend-check $(date +%s)"
echo "$mark" | sudo tee /dev/kmsg >/dev/null

echo "== $(grep -oE '(clk_ignore_unused|pd_ignore_unused|fw_devlink.sync_state=[a-z]+)' /proc/cmdline | tr '\n' ' ')"
echo "== suspending drivers (pm_test=devices), back in ~5 s ..."
sudo sh -c 'echo devices > /sys/power/pm_test; echo mem > /sys/power/state; echo none > /sys/power/pm_test'
echo "== resumed at $(date +%T); testing storage (direct I/O, 10 s limit) ..."

ok=1
timeout 10 dd if=/dev/urandom of="$f" bs=1M count=8 oflag=direct status=none || ok=0
[ $ok = 1 ] && { timeout 10 dd if="$f" of=/dev/null bs=1M iflag=direct status=none || ok=0; }
rm -f "$f" 2>/dev/null

echo "== kernel messages since the mark (storage, PM, errors):"
sudo dmesg | sed -n "/$mark/,\$p" | grep -iE "ufs|scsi|sd [0-9]|i/o error|btrfs|blk_|error|fail|timeout|hung" | tail -25
if [ $ok = 1 ]; then
    echo "== STORAGE OK after resume"
else
    echo "== STORAGE FAILED after resume  <- photograph this screen, then hold the power button"
fi
