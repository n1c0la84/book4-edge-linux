#!/usr/bin/env bash
# Is the Bluetooth UART the last XO holder? The serial port a98000 stays open
# while hci_uart_qca is bound, keeping gcc_qupv3_wrap1_s6_clk -> GPLL0 ->
# bi_tcxo prepared, so xo.lvl is voted on through suspend (16 Oct trace).
# Unbind the Bluetooth driver, check the clock, suspend once (wake it after
# ~2 min), compare the SoC sleep counters, rebind. Bluetooth is off meanwhile.
# Best on "test: ufsfix-trace" / "test: ufsfix" after a sync run; any boot works.
# Run as yourself: bash ~/bt-unbind-test.sh
set -euo pipefail
dev=serial0-0
drv=/sys/bus/serial/drivers/hci_uart_qca
st=/sys/kernel/debug/qcom_stats
sudo -v
cnt() { for s in aosd cxsd ddr; do printf "%s=%s " $s "$(sudo awk '/^Count/{print $2}' $st/$s)"; done; }
clk() { sudo awk '$1=="gcc_qupv3_wrap1_s6_clk"{print "enable="$2" prepare="$3; exit}' /sys/kernel/debug/clk/clk_summary; }
echo "before: $(cnt) | BT UART clock $(clk)"
printf $dev | sudo tee $drv/unbind >/dev/null
sleep 2
echo "Bluetooth unbound | BT UART clock $(clk)"
ok0=$(cat /sys/power/suspend_stats/success); fail0=$(cat /sys/power/suspend_stats/fail)
echo "suspending in 3 s (wake it after ~2 min) ..."; sleep 3
systemctl suspend
while [ "$(cat /sys/power/suspend_stats/success)" = "$ok0" ] && [ "$(cat /sys/power/suspend_stats/fail)" = "$fail0" ]; do sleep 1; done
sleep 3
echo "after:  $(cnt)"
printf $dev | sudo tee $drv/bind >/dev/null && sleep 3
echo "Bluetooth rebound: $(bluetoothctl show 2>/dev/null | grep -m1 Powered || echo '?')"
