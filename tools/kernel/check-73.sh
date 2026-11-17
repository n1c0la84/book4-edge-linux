#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# On a boot of the 7.3 kernel (tools/kernel/build-73-kernel.sh): what works,
# in one pass, written to ~/check-73.txt. Run as your user (sudo for debugfs).
set -uo pipefail
out=$HOME/check-73.txt
sudo -v
{
echo "== $(date)  $(uname -r)  $(journalctl -k -b -o cat | grep -m1 'started at EL')"
echo "-- DC ZVA workaround: $(journalctl -k -b -o cat | grep -c 'Broken DC ZVA') line(s)"
echo "-- DSPs: $(for r in /sys/class/remoteproc/remoteproc*; do printf '%s=%s ' "$(cat $r/name)" "$(cat $r/state)"; done)"
echo "-- sound cards: $(grep -c '^ *[0-9]' /proc/asound/cards 2>/dev/null)"
echo "-- power supplies: $(ls /sys/class/power_supply | tr '\n' ' ')"
for p in /sys/class/power_supply/*; do echo "   $(basename $p): $(cat $p/status 2>/dev/null) $(cat $p/capacity 2>/dev/null)% online=$(cat $p/online 2>/dev/null)"; done
echo "-- typec: $(ls /sys/class/typec 2>/dev/null | tr '\n' ' ')"
echo "-- wifi: $(ip -br link show wlan0 2>/dev/null)"
echo "-- bluetooth: $(bluetoothctl show 2>/dev/null | grep -m1 Powered)"
echo "-- camera: $(ls /dev/video* 2>/dev/null | wc -l) video nodes"
echo "-- fingerprint: $(cat /sys/bus/usb/devices/*/idVendor 2>/dev/null | grep -c 1c7a)"
echo "-- kvm: $([ -e /dev/kvm ] && echo yes || echo no)"
echo "-- TPM: $(ls /dev/tpm* 2>/dev/null | tr '\n' ' ')"
echo "-- EFI vars: $(ls /sys/firmware/efi/efivars 2>/dev/null | wc -l)"
echo "-- sleep modules: $(lsmod | grep -oE '^(el1tmr|aoss_cxsd_only|icc_hold)' | tr '\n' ' ')"
echo "-- book4-el2-sleep.service: $(systemctl is-active book4-el2-sleep.service)"
echo "-- providers not synced: $(grep -L 1 $(find /sys/devices -name state_synced 2>/dev/null) 2>/dev/null | tr '\n' ' ')"
echo "-- sleep counters:"; for s in apss aosd cxsd ddr; do echo "   $s: $(sudo cat /sys/kernel/debug/qcom_stats/$s 2>/dev/null | tr '\n' ' ')"; done
echo "-- failed units: $(systemctl --failed --no-legend | awk '{print $2}' | tr '\n' ' ')"
echo "-- kernel errors:"; journalctl -k -b -p err -o cat | sort | uniq -c | sort -rn | head -30
} > "$out" 2>&1
cat "$out"
echo; echo "Saved to $out. Then: one sleep on battery (the sleep log tags it with the kernel)."
