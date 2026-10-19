#!/usr/bin/env bash
# What does Linux leave voted at RPMh while asleep? Saves the RPMh command
# trace (rpmh:rpmh_send_msg) and the cmd-db map, around one short suspend.
# Wake it after ~30 s. Output: ~/src/book4-acpi/linux-state/rpmh-sleepset-TIME/
#
# Best on the boot entry "test: ufsfix-trace" (made by ~/rpmh-trace-prep.sh),
# which traces RPMh from boot, so every vote ever sent is in the buffer.
#   bash ~/rpmh-sleepset.sh sync   also forces every provider's sync_state
#                                  first (with the active-only UFS hold), as
#                                  in the drips-full runs
# Run as yourself.
set -euo pipefail
out=$HOME/src/book4-acpi/linux-state/rpmh-sleepset-$(date +%Y%m%d-%H%M%S)
mkdir -p "$out"
t=/sys/kernel/tracing
repo=$HOME/Projects/book4-edge-linux
sudo -v
sudo test -d $t/events/rpmh || { echo "error: no rpmh trace events in $t" >&2; exit 1; }
if [ "${1:-}" = sync ]; then
  grep -q '^icc_hold ' /proc/modules || sudo insmod "$repo/tools/power/icc-hold/icc_hold.ko" nodes=/soc@0/ufshc@1d84000 tag=3
  for p in $(find /sys/devices -name state_synced 2>/dev/null); do
    [ "$(cat "$p")" = 1 ] || printf 1 | sudo tee "$p" >/dev/null
  done
  echo "providers synced; settling 10 s"; sleep 10
fi
# cmd-db: a file or a directory depending on the kernel
if sudo test -f /sys/kernel/debug/cmd-db; then sudo cat /sys/kernel/debug/cmd-db > "$out/cmd-db.txt"
else sudo sh -c 'for f in /sys/kernel/debug/cmd-db/*; do echo "== $f"; cat "$f"; done' > "$out/cmd-db.txt" 2>&1; fi
if grep -q 'trace_event=rpmh' /proc/cmdline; then
  echo "tracing since boot: keeping the buffer"
else
  echo 0 | sudo tee $t/tracing_on >/dev/null
  echo | sudo tee $t/trace >/dev/null
  echo 16384 | sudo tee $t/buffer_size_kb >/dev/null
  echo 1 | sudo tee $t/events/rpmh/enable >/dev/null
fi
# Kernel stack for every SN4 (system NoC) bus vote, to see which driver casts it.
echo 'stacktrace if addr == 0x50020' | sudo tee $t/events/rpmh/rpmh_send_msg/trigger >/dev/null
echo 1 | sudo tee $t/tracing_on >/dev/null
cat /proc/cmdline > "$out/cmdline.txt"
ok0=$(cat /sys/power/suspend_stats/success); fail0=$(cat /sys/power/suspend_stats/fail)
echo "suspending in 3 s (wake it after ~30 s) ..."; sleep 3
systemctl suspend
while [ "$(cat /sys/power/suspend_stats/success)" = "$ok0" ] && [ "$(cat /sys/power/suspend_stats/fail)" = "$fail0" ]; do sleep 1; done
[ "$(cat /sys/power/suspend_stats/fail)" = "$fail0" ] || echo "warning: the suspend FAILED ($(cat /sys/power/suspend_stats/last_failed_dev) $(cat /sys/power/suspend_stats/last_failed_errno))"
sleep 2
echo 0 | sudo tee $t/tracing_on >/dev/null
sudo cat $t/trace > "$out/trace.txt"
echo '!stacktrace if addr == 0x50020' | sudo tee $t/events/rpmh/rpmh_send_msg/trigger >/dev/null 2>&1 || true
for s in aosd cxsd ddr; do printf "%s=%s " $s "$(sudo awk '/^Count/{print $2}' /sys/kernel/debug/qcom_stats/$s)"; done > "$out/counters.txt"
echo "trace: $(grep -c rpmh_send_msg "$out/trace.txt") commands, first at $(grep -m1 -o '[0-9]*\.[0-9]*: rpmh' "$out/trace.txt" | cut -d: -f1) s; cmd-db $(wc -l < "$out/cmd-db.txt") lines"
echo "saved in $out"
