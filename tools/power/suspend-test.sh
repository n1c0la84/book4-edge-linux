#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# s2idle test: does the SoC reach its low-power states?
# Compares the qcom_stats counters (aosd = AOSS sleep, cxsd = CX rail
# collapse, ddr = DDR self-refresh) before and after one suspend.
# The RTC cannot wake this machine: wake it yourself (lid or power key)
# after about a minute. Run as your user.
set -u
S=/sys/kernel/debug/qcom_stats
OUT=~/suspend-test-$(uname -r)-$(date +%H%M).txt
snap() { sudo sh -c "for f in aosd cxsd ddr apss adsp cdsp; do printf '%s: ' \$f; tr '\n' ' ' < $S/\$f; echo; done"; }

sudo -v
{
echo "kernel $(uname -r), $(date)"
echo "== before"; snap
n=$(cat /sys/power/suspend_stats/success); f=$(cat /sys/power/suspend_stats/fail)
echo "== suspending at $(date +%T): wait ~1 min, then open the lid / press power"
systemctl suspend
while [ "$(cat /sys/power/suspend_stats/success)" = "$n" ] && \
      [ "$(cat /sys/power/suspend_stats/fail)" = "$f" ]; do sleep 1; done
sleep 3
echo "== resumed at $(date +%T)"
echo "== after"; snap
echo "== suspend_stats"; grep -r . /sys/power/suspend_stats/ | sed 's|.*/||'
echo "== kernel log"
sudo dmesg | grep -iE 'PM: |s2idle|suspend|resum|wakeup|Freezing|failed|timeout' | tail -30
} 2>&1 | tee "$OUT"
echo; echo "saved to $OUT"
