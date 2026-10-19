#!/usr/bin/env bash
# Which clocks are still enabled when the SoC goes to sleep? xo.lvl (the RPMh
# XO vote of bi_tcxo) never drops, so some clock below bi_tcxo stays on.
# clk-rpmh votes in prepare, so prepared-but-disabled clocks count too.
# Baseline clk_summary, then trace clk enable/disable/prepare/unprepare (and RPMh)
# across one suspend; the parser reconstructs the clock state at the moment
# rpmhpd votes CX off (end of noirq suspend). Wake it after ~30 s.
# Output: ~/src/book4-acpi/linux-state/clk-at-suspend-TIME/
# Run as yourself: bash ~/clk-at-suspend.sh [sync] [nobt]
set -euo pipefail
out=$HOME/src/book4-acpi/linux-state/clk-at-suspend-$(date +%Y%m%d-%H%M%S)
mkdir -p "$out"
t=/sys/kernel/tracing
sudo -v
echo 0 | sudo tee $t/tracing_on >/dev/null
echo | sudo tee $t/trace >/dev/null
echo 16384 | sudo tee $t/buffer_size_kb >/dev/null
for e in clk/clk_enable clk/clk_disable clk/clk_prepare clk/clk_unprepare rpmh/rpmh_send_msg; do
  echo 1 | sudo tee $t/events/$e/enable >/dev/null
done
repo=$HOME/Projects/book4-edge-linux
if [[ " $* " == *" sync "* ]]; then   # release the firmware's boot votes (as in drips-full)
  grep -q '^icc_hold ' /proc/modules || sudo insmod "$repo/tools/power/icc-hold/icc_hold.ko" nodes=/soc@0/ufshc@1d84000 tag=3
  for p in $(find /sys/devices -name state_synced 2>/dev/null); do
    [ "$(cat "$p")" = 1 ] || printf 1 | sudo tee "$p" >/dev/null
  done
  echo "providers synced; settling 10 s"; sleep 10
fi
if [[ " $* " == *" nobt "* ]]; then   # close the Bluetooth UART first (rebound at the end)
  printf serial0-0 | sudo tee /sys/bus/serial/drivers/hci_uart_qca/unbind >/dev/null; sleep 2
  trap 'printf serial0-0 | sudo tee /sys/bus/serial/drivers/hci_uart_qca/bind >/dev/null' EXIT
fi
sudo cat /sys/kernel/debug/clk/clk_summary > "$out/clk_summary.txt"
for s in aosd cxsd ddr; do printf "%s=%s " $s "$(sudo awk '/^Count/{print $2}' /sys/kernel/debug/qcom_stats/$s)"; done > "$out/counters-before.txt"
echo 1 | sudo tee $t/tracing_on >/dev/null
ok0=$(cat /sys/power/suspend_stats/success); fail0=$(cat /sys/power/suspend_stats/fail)
echo "suspending in 3 s (wake it after ~2 min) ..."; sleep 3
systemctl suspend
while [ "$(cat /sys/power/suspend_stats/success)" = "$ok0" ] && [ "$(cat /sys/power/suspend_stats/fail)" = "$fail0" ]; do sleep 1; done
sleep 2
echo 0 | sudo tee $t/tracing_on >/dev/null
sudo cat $t/trace > "$out/trace.txt"
for s in aosd cxsd ddr; do printf "%s=%s " $s "$(sudo awk '/^Count/{print $2}' /sys/kernel/debug/qcom_stats/$s)"; done > "$out/counters-after.txt"
echo "counters before: $(cat "$out/counters-before.txt") after: $(cat "$out/counters-after.txt")"
for e in clk/clk_enable clk/clk_disable clk/clk_prepare clk/clk_unprepare; do echo 0 | sudo tee $t/events/$e/enable >/dev/null; done
echo "saved in $out ($(grep -c -E 'clk_(en|dis)able:|clk_(un)?prepare:' "$out/trace.txt") clock transitions)"
