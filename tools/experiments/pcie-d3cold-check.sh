#!/usr/bin/env bash
# On the "test: drips-pcie" boot: one short suspend (wake it after ~1 min),
# then show whether the PCIe controller went through D3cold (a fresh
# "link up" after resume) and whether Wi-Fi is back by itself.
# Run as yourself: bash ~/pcie-d3cold-check.sh
set -euo pipefail
grep -qw pcie_port_pm=force /proc/cmdline || { echo "error: boot 'test: drips-pcie'" >&2; exit 1; }
sudo -v
mark=$(sudo dmesg | wc -l)
ok0=$(cat /sys/power/suspend_stats/success); fail0=$(cat /sys/power/suspend_stats/fail)
echo "suspending in 5 s; wake it after about a minute ..."
sleep 5
systemctl suspend
while [ "$(cat /sys/power/suspend_stats/success)" = "$ok0" ] && [ "$(cat /sys/power/suspend_stats/fail)" = "$fail0" ]; do sleep 1; done
sleep 3
echo "== kernel messages during the suspend (PCIe / Wi-Fi):"
sudo dmesg | tail -n +$((mark + 1)) | grep -v UFW | grep -i -E 'qcom-pcie|0004:|ath12k|mhi|L2|pcieport|PM: suspend' | head -30
for i in $(seq 60); do nmcli -t -f DEVICE,STATE dev | grep -q '^wlan0:connected' && break; sleep 1; done
echo "== Wi-Fi after ${i} s: $(nmcli -t -f DEVICE,STATE dev | grep '^wlan0' || echo none)"
echo "== power states: root port $(cat /sys/bus/pci/devices/0004:00:00.0/power_state), card $(cat /sys/bus/pci/devices/0004:01:00.0/power_state 2>/dev/null || echo absent)"
