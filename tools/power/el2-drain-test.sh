#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Measure one suspend in the daily EL2 configuration, ON BATTERY: charge
# before/after (tools/power/sleep-drain.sh, logged) and the residency, the
# time spent in aosd/cxsd/ddr out of the time asleep. book4-el2-sleep.service
# (install/el2/sleep-setup.sh) normally prepares the boot (el1tmr, UFS hold,
# boot votes released); if it has not run, this does the same by hand.
# Also prints the DSP states and the LPASS votes Linux holds at the ADSP
# (both 0 when idle since sleep-backport 0024/0025).
# Wake it yourself after 10-60 min (shorter runs only give residency).
# Run as yourself: bash tools/power/el2-drain-test.sh
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
st=/sys/kernel/debug/qcom_stats
[ "$(uname -r)" = 7.2.7-book4s ] || { echo "error: not the sleep kernel 7.2.7-book4s (boot the EL2 entry)" >&2; exit 1; }
journalctl -k -b -o cat | grep -c 'All CPU(s) started at EL2' >/dev/null || { echo "error: not an EL2 boot" >&2; exit 1; }
[ "$(cat /sys/class/power_supply/samsung-galaxybook-battery/status)" != Charging ] || { echo "error: unplug the charger first" >&2; exit 1; }
sudo -v
# Not qcom_adsp_pwr_lmts: Windows itself does not send that message on the
# Book4 (Samsung's qcadc8380_ext.inf sets EnablePowerLimitsInterface=0) and
# the ADSP crashes on it. Blacklisted by install/el2/sleep-setup.sh.
grep -q '^qcom_adsp_pwr_lmts ' /proc/modules && { echo "error: qcom_adsp_pwr_lmts is loaded; it crashes the ADSP (bash install/el2/sleep-setup.sh, reboot)" >&2; exit 1; }
echo "   book4-el2-sleep.service: $(systemctl is-active book4-el2-sleep.service || true)"
echo "   DSPs: $(for r in /sys/class/remoteproc/*; do printf '%s=%s ' $(cat $r/name) $(cat $r/state); done)"
echo "   LPASS votes at the ADSP: $(for c in LPASS_HW_MACRO LPASS_HW_DCODEC; do printf '%s=%s ' $c "$(sudo cat /sys/kernel/debug/clk/$c/clk_enable_count 2>/dev/null || echo -)"; done)"
grep -q '^el1tmr ' /proc/modules || sudo modprobe el1tmr
grep -q '^icc_hold ' /proc/modules || sudo modprobe icc_hold nodes=/soc@0/ufshc@1d84000 tag=3
for p in $(find /sys/devices -name state_synced 2>/dev/null); do
  [ "$(cat "$p")" = 1 ] || printf 1 | sudo tee "$p" >/dev/null
done
sleep 5
acc() { for s in aosd cxsd ddr; do printf '%s ' "$(sudo awk -F: '/Accumulated Duration/{gsub(/ /,"",$2); print $2}' $st/$s)"; done; }
a0=($(acc)); ok0=$(cat /sys/power/suspend_stats/success)
bash "$repo/tools/power/sleep-drain.sh" el2-sleep
a1=($(acc))
echo "   DSPs after: $(for r in /sys/class/remoteproc/*; do printf '%s=%s ' $(cat $r/name) $(cat $r/state); done)"
c=$(sudo dmesg | grep -c 'crash detected in adsp' || true); echo "   ADSP crashes this boot: $c"
slept=$(journalctl -b -o short-unix --no-pager | awk '/PM: suspend entry/{e=$1} /PM: suspend exit/{x=$1} END{printf "%d", x-e}')
echo "== residency over ~${slept} s asleep (accumulated time, 19.2 MHz ticks):"
i=0; for s in aosd cxsd ddr; do
  d=$(( ${a1[$i]} - ${a0[$i]} ))
  awk -v s=$s -v d=$d -v t=$slept 'BEGIN{sec=d/19200000; printf "   %-4s %8.1f s  (%.1f %%)\n", s, sec, (t>0 ? 100*sec/t : 0)}'
  i=$((i+1))
done
