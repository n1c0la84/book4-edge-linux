#!/usr/bin/env bash
# On "test: el2-drips", after spss-stop-test.sh: are the always-asserted
# (disabled) interrupt lines what makes TrustZone return from DRIPS at once?
# Silence their sources for one probe suspend (wake it after ~30 s):
# Bluetooth (hci_uart + UART a98000, SPI 806), the debug UART 894000 (SPI 813),
# Wi-Fi (PCI remove, SPI 156). Restores them at the end (Wi-Fi via rescan).
# Left: SPI 352 (SPSS) and SPI 533 (usb_1_ss2, no driver bound).
# Run as yourself: bash ~/quiet-lines-test.sh
set -euo pipefail
p=$HOME/Projects/book4-edge-linux/tools/power
grep -q 'id_aa64mmfr0.ecv' /proc/cmdline || { echo "error: boot an EL2 entry (test: el2-drips)" >&2; exit 1; }
sudo -v
restore() {
  printf a98000.serial | sudo tee /sys/bus/platform/drivers/qcom_geni_serial/bind >/dev/null 2>&1 || true
  printf 894000.serial | sudo tee /sys/bus/platform/drivers/qcom_geni_serial/bind >/dev/null 2>&1 || true
  printf 1 | sudo tee /sys/bus/pci/rescan >/dev/null 2>&1 || true
  sleep 3
  echo "restored: wifi=$(ls /sys/bus/pci/devices | tr '\n' ' ')bt=$(ls /sys/class/bluetooth 2>/dev/null | tr '\n' ' ')"
}
trap restore EXIT
[ -e /sys/bus/serial/drivers/hci_uart_qca/serial0-0 ] && printf serial0-0 | sudo tee /sys/bus/serial/drivers/hci_uart_qca/unbind >/dev/null
for s in a98000.serial 894000.serial; do
  [ -e /sys/bus/platform/drivers/qcom_geni_serial/$s ] && printf $s | sudo tee /sys/bus/platform/drivers/qcom_geni_serial/unbind >/dev/null
done
[ -e /sys/bus/pci/devices/0004:01:00.0 ] && printf 1 | sudo tee /sys/bus/pci/devices/0004:01:00.0/remove >/dev/null
sleep 3
sudo rmmod timer_check gic_pending 2>/dev/null || true
sudo insmod $p/timer-check/timer_check.ko disable=1
sudo insmod $p/gic-pending/gic_pending.ko clear=1 ppi_off=0x08000000
bash ~/el2-probe.sh
sudo rmmod gic_pending timer_check
sudo dmesg | grep -E 'gic_pending: [0-9]|gic_pending:   INTID' | tail -21 | head -10
