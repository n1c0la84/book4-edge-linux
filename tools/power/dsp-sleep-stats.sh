#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Which DSP stays awake (and keeps CX up) during s2idle? Reads the Qualcomm
# sleep stats of the ADSP and CDSP (and aosd/cxsd/ddr) before and after one
# suspend. Wake it after ~2 min. Any boot. Run as yourself: bash tools/power/dsp-sleep-stats.sh
set -euo pipefail
st=/sys/kernel/debug/qcom_stats
sudo -v
names=$(sudo ls $st | tr '\n' ' '); echo "qcom_stats: $names"
snap() { for s in $(sudo ls $st); do sudo awk -v s=$s -F': *' '/^Count/{c=$2} /^Accumulated Duration/{a=$2} END{printf "%s %s %s\n", s, c, a}' $st/$s; done; }
snap > /tmp/dss0.$$
ok0=$(cat /sys/power/suspend_stats/success); fail0=$(cat /sys/power/suspend_stats/fail)
echo "suspending in 3 s (wake it after ~2 min) ..."; sleep 3
t0=$(date +%s); systemctl suspend
while [ "$(cat /sys/power/suspend_stats/success)" = "$ok0" ] && [ "$(cat /sys/power/suspend_stats/fail)" = "$fail0" ]; do sleep 1; done
t1=$(date +%s); sleep 2
snap > /tmp/dss1.$$
echo "== during ~$((t1 - t0)) s (sleeps entered, time asleep in s at 19.2 MHz):"
join /tmp/dss0.$$ /tmp/dss1.$$ | awk -v t=$((t1 - t0)) '{dc=$4-$2; da=($5-$3)/19200000; printf "   %-14s +%-6d %8.1f s (%.0f %%)\n", $1, dc, da, (t>0?100*da/t:0)}'
rm -f /tmp/dss0.$$ /tmp/dss1.$$
echo "DSPs: $(for r in /sys/class/remoteproc/*; do printf '%s=%s ' $(cat $r/name) $(cat $r/state); done)"
