#!/usr/bin/env bash
# Linux's own RPMh votes are all off at sleep (16 Oct clean trace), yet the
# SoC never collapses. Do the DSPs hold CX/XO through their own RPMh DRVs?
# Stop adsp + cdsp (no sound meanwhile), release boot votes, unbind Bluetooth,
# suspend once (wake it after ~2 min), compare counters, restart everything.
# Fresh boot of "test: ufsfix" / "test: ufsfix-trace" recommended; also works
# at EL2 ("test: el2-drips"), where the DSPs never start.
# Run as yourself: bash ~/dsp-stop-test.sh
set -euo pipefail
repo=$HOME/Projects/book4-edge-linux
st=/sys/kernel/debug/qcom_stats
sudo -v
cnt() { for s in aosd cxsd ddr adsp cdsp; do printf "%s=%s " $s "$(sudo awk '/^Count/{print $2}' $st/$s)"; done; }
restore() {
  for r in /sys/class/remoteproc/remoteproc*; do
    [ "$(cat $r/state)" = offline ] && ! grep -q 'id_aa64mmfr0.ecv' /proc/cmdline && printf start | sudo tee $r/state >/dev/null || true
  done
  printf serial0-0 | sudo tee /sys/bus/serial/drivers/hci_uart_qca/bind >/dev/null 2>&1 || true
  echo "restored: $(for r in /sys/class/remoteproc/remoteproc*; do printf '%s=%s ' $(cat $r/name) $(cat $r/state); done)"
}
trap restore EXIT
grep -q '^icc_hold ' /proc/modules || sudo insmod "$repo/tools/power/icc-hold/icc_hold.ko" nodes=/soc@0/ufshc@1d84000 tag=3
for p in $(find /sys/devices -name state_synced 2>/dev/null); do
  [ "$(cat "$p")" = 1 ] || printf 1 | sudo tee "$p" >/dev/null
done
[ -e /sys/bus/serial/drivers/hci_uart_qca/serial0-0 ] && printf serial0-0 | sudo tee /sys/bus/serial/drivers/hci_uart_qca/unbind >/dev/null
echo "before: $(cnt)"
for r in /sys/class/remoteproc/remoteproc*; do
  [ "$(cat $r/state)" = running ] && printf stop | sudo tee $r/state >/dev/null
  echo "  $(cat $r/name): $(cat $r/state)"
done
sleep 5
ok0=$(cat /sys/power/suspend_stats/success); fail0=$(cat /sys/power/suspend_stats/fail)
echo "suspending in 3 s (wake it after ~2 min) ..."; sleep 3
systemctl suspend
while [ "$(cat /sys/power/suspend_stats/success)" = "$ok0" ] && [ "$(cat /sys/power/suspend_stats/fail)" = "$fail0" ]; do sleep 1; done
[ "$(cat /sys/power/suspend_stats/fail)" = "$fail0" ] || echo "warning: the suspend FAILED ($(cat /sys/power/suspend_stats/last_failed_dev))"
sleep 3
echo "after:  $(cnt)"
