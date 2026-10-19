#!/usr/bin/env bash
# Awake test: can the Wi-Fi card be removed from PCI and brought back without
# the old panic (docs/firmware.md: ath12k_qmi_phy_cap_send)? If yes, a sleep
# hook can take the link down for suspend. Save your work first: a panic means
# a hard reboot (hold power 10 s). Each step is logged and synced to
#   ~/src/book4-acpi/linux-state/wifi-remove-test.log
# Run as yourself: bash ~/wifi-remove-test.sh
set -euo pipefail
dev=0004:01:00.0
port=/sys/bus/pci/devices/0004:00:00.0
log=$HOME/src/book4-acpi/linux-state/wifi-remove-test.log
step() { echo "== $(date +%T) $*" | tee -a "$log"; sync; }
dmesg_tail() { sudo dmesg | tail -n "${1:-15}" | tee -a "$log"; sync; }

[ -e /sys/bus/pci/devices/$dev ] || { echo "error: Wi-Fi ($dev) not present" >&2; exit 1; }
sudo -v
step "start: $(uname -r), $(tr -d '\0' < /proc/cmdline)"
step "ath12k firmware: $(sudo dmesg | grep -m1 -o 'fw_version 0x[0-9a-f]*.*' || echo '?')"
step "link before: $(cat /sys/bus/pci/devices/$dev/current_link_speed 2>/dev/null) / $(nmcli -t -f DEVICE,STATE dev 2>/dev/null | grep -i wl || echo no-nm)"
sleep 3

step "1. remove $dev (unbinds ath12k)"
printf 1 | sudo tee /sys/bus/pci/devices/$dev/remove >/dev/null
sleep 3; dmesg_tail 20
step "1. survived the remove"

step "2. rescan $port"
printf 1 | sudo tee $port/rescan >/dev/null
sleep 10; dmesg_tail 30
step "2. survived the rescan; device present: $([ -e /sys/bus/pci/devices/$dev ] && echo yes || echo NO)"

sleep 15
step "3. Wi-Fi after 25 s: $(nmcli -t -f DEVICE,STATE dev 2>/dev/null | grep -i wl || ip -br link | grep -i wl || echo none)"
echo "log: $log"
