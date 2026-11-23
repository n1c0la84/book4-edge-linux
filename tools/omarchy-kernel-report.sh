#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Snapshot of how a boot looks (written for the linux-omarchy test boots,
# install/arch/omarchy-kernel-test.sh; works on any kernel). No network and
# no root needed. Run on the boot to look at:
#
#   bash ~/Projects/book4-edge-linux/tools/omarchy-kernel-report.sh
#
# Writes ~/boot-report-<kernel>-<time>.txt. The journal of that boot is kept
# anyway (journalctl -b -1 from the next boot); this adds device states.
out=~/boot-report-$(uname -r)-$(date +%Y%m%d-%H%M).txt
sec() { printf '\n===== %s\n' "$1"; }
{
sec "kernel and boot"
uname -a; cat /proc/cmdline; uptime
journalctl -k -b --no-pager | grep -E "started at EL|Machine model|DMI:" | head -5
for v in LoaderInfo LoaderEntrySelected StubInfo; do
    f=$(ls /sys/firmware/efi/efivars/$v-* 2>/dev/null | head -1)
    [ -n "$f" ] && printf '%s: %s\n' "$v" "$(tail -c +5 "$f" | tr -d '\0')"
done
ls -l /dev/kvm 2>&1
sec "failed units"
systemctl --failed --no-legend --no-pager
sec "remoteprocs (ADSP, CDSP)"
for r in /sys/class/remoteproc/*; do echo "$(cat "$r/name") $(cat "$r/state")"; done
sec "sound"
aplay -l 2>&1 | grep card
for d in /sys/bus/soundwire/devices/sdw:*; do echo "$(basename "$d") $(cat "$d/status" 2>/dev/null)"; done
wpctl status 2>&1 | sed -n '/Audio/,/Video/p' | head -25
sec "battery and USB-C (EC)"
for p in /sys/class/power_supply/*; do
    echo "$(basename "$p"): $(cat "$p/status" 2>/dev/null) $(cat "$p/capacity" 2>/dev/null)% online=$(cat "$p/online" 2>/dev/null)"
done
ls /sys/class/typec 2>&1
sec "network"
ip -br link; rfkill list 2>&1; nmcli -t device 2>&1 | head; iwctl station list 2>&1 | head
sec "bluetooth"
bluetoothctl show 2>&1 | head -8
sec "camera, fingerprint, input"
cam -l 2>&1 | head -5
lsusb 2>&1
grep -E "^N: Name" /proc/bus/input/devices
sec "display and GPU"
ls /sys/class/drm/
cat /sys/class/drm/card*-eDP-1/status /sys/class/drm/card*-eDP-1/modes 2>/dev/null | head -3
sec "modules loaded"
lsmod | sort | awk '{print $1}' | tr '\n' ' '; echo
sec "kernel warnings and errors (this boot)"
journalctl -k -b -p warning --no-pager | tail -150
sec "firmware load failures"
journalctl -k -b --no-pager | grep -i -E "firmware|direct firmware load" | grep -i -E "fail|error|not found" | head -40
} > "$out" 2>&1
echo "Written: $out"
