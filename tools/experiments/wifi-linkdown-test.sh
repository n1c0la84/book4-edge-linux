#!/usr/bin/env bash
# Awake test, no suspend: take the Wi-Fi link fully down (remove the card,
# Link Disable on the root port) and bring it back through the hotplug slot.
# If Wi-Fi does not return within 90 s, a reboot fixes it. Log (synced):
#   ~/src/book4-acpi/linux-state/wifi-linkdown-test.log
# Run as yourself: bash ~/wifi-linkdown-test.sh
set -euo pipefail
dev=0004:01:00.0; port=0004:00:00.0; slot=/sys/bus/pci/slots/0
log=$HOME/src/book4-acpi/linux-state/wifi-linkdown-test.log
step() { echo "== $(date +%T) $*" | tee -a "$log"; sync; }
linkst() { sudo lspci -vv -s $port | grep -A1 'LnkSta:' | grep -o -E 'DLActive[+-]' | tr '\n' ' '; sudo lspci -vv -s $port | grep -o 'LnkDisable[+-]'; }
[ -e /sys/bus/pci/devices/$dev ] || { echo "error: Wi-Fi ($dev) not present" >&2; exit 1; }
sudo -v
mark=$(sudo dmesg | wc -l)
step "start: link $(linkst), slot power $(cat $slot/power)"
printf 1 | sudo tee /sys/bus/pci/devices/$dev/remove >/dev/null; sleep 2
sudo setpci -s $port CAP_EXP+10.w=0010:0010; sleep 3
step "link disabled: link $(linkst), slot power $(cat $slot/power)"
sudo setpci -s $port CAP_EXP+10.w=0000:0010; sleep 2
step "link re-enabled: link $(linkst), slot power $(cat $slot/power)"
[ "$(cat $slot/power)" = 1 ] || { printf 1 | sudo tee $slot/power >/dev/null; sleep 3; step "slot powered on: link $(linkst)"; }
[ -e /sys/bus/pci/devices/$dev ] || { printf 1 | sudo tee /sys/bus/pci/devices/$port/rescan >/dev/null; step "rescanned"; }
for i in $(seq 90); do ip -br link | grep -q '^wl' && break; sleep 1; done
step "Wi-Fi after ${i} s: $(ip -br link | grep wl || echo NONE)"
sudo dmesg | tail -n +$((mark + 1)) | grep -i -E 'pciehp|qcom-pcie|0004:|ath12k|mhi' | grep -v 'UFW' | tee -a "$log"; sync
