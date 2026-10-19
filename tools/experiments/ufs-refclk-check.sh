#!/usr/bin/env bash
# Does UFS leak enables on its ref_clk (RPMh clk8, an XO buffer)? Prints
# clk8's enable count, suspends (wake it after ~20 s), prints it again.
# If it grows on every cycle, the sleep-set XO vote can never drop.
# Any boot. Run as yourself: bash ~/ufs-refclk-check.sh
set -euo pipefail
sudo -v
cnt() { sudo awk '$1=="clk8"{print $2; exit}' /sys/kernel/debug/clk/clk_summary; }
echo "clk8 enable count now: $(cnt)"
for i in 1 2; do
  ok0=$(cat /sys/power/suspend_stats/success); fail0=$(cat /sys/power/suspend_stats/fail)
  echo "suspend $i in 3 s (wake it after ~20 s) ..."; sleep 3
  systemctl suspend
  while [ "$(cat /sys/power/suspend_stats/success)" = "$ok0" ] && [ "$(cat /sys/power/suspend_stats/fail)" = "$fail0" ]; do sleep 1; done
  sleep 5
  echo "clk8 enable count after resume $i: $(cnt)"
done
