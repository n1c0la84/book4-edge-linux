#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Real s2idle with the charging port driver BOUND (for testing a driver fix,
# e.g. patches-experimental/0004); power-button wake, then a 90 s watch for
# a delayed reset.
# Experimental hardware diagnostic; see docs/power.md before running.
set -euo pipefail
mode=${1:-}
case "$mode" in control|unplug) ;; *) echo "Usage: sudo bash $0 control|unplug" >&2; exit 2;; esac
[[ $EUID -eq 0 ]] || { echo 'Run with sudo from a terminal.'; exit 1; }
[[ $(cat /sys/power/pm_test) == *'[none]'* ]] || { echo 'Another PM test is selected; stopping.'; exit 1; }
[[ $(cat /sys/power/mem_sleep) == *'[s2idle]'* ]] || { echo 'Expected s2idle; stopping.'; exit 1; }
ac=/sys/class/power_supply/samsung-galaxybook-ac/online
[[ $(cat "$ac") == 1 ]] || { echo 'Connect the charger, wait until detected, then run again.'; exit 1; }
echo 'Keep the lid open and save your work. This test enters real s2idle sleep.'
if [[ $mode == control ]]; then
    echo 'CONTROL: keep the charger connected; after 60 seconds asleep, briefly press the power button once.'
else
    echo 'UNPLUG: after 60 seconds asleep, unplug; wait another 60 seconds, then briefly press the power button once.'
fi
echo 'There is no automatic 30-second recovery in this test.'
read -r -p 'Press Enter to start, or Ctrl-C to cancel. ' _
[[ $(cat "$ac") == 1 ]] || { echo 'Charger is no longer detected; stopping.'; exit 1; }
log_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
log_file="$log_dir/s2idle-bound-$mode-$(date +%Y%m%d-%H%M%S).log"
pdic_driver=/sys/bus/i2c/drivers/samsung-emuec
ports=()
for dev in "$pdic_driver"/*-0033; do
    [[ -L $dev ]] || continue
    name=${dev##*/}
    online=/sys/class/power_supply/$name-usb/online
    if [[ -f $online && $(cat "$online") == 1 ]]; then ports+=("$name"); fi
done
[[ ${#ports[@]} == 1 ]] || { echo 'Expected exactly one connected charger port; stopping.'; exit 1; }
pdic_port=${ports[0]}
unbound=0
old_debug=$(cat /sys/power/pm_debug_messages)
restore() {
    local rc=$?
    trap - EXIT
    printf 'none\n' > /sys/power/pm_test || true
    printf '%s\n' "$old_debug" > /sys/power/pm_debug_messages || true
    if [[ $unbound == 1 && ! -L /sys/bus/i2c/devices/$pdic_port/driver ]]; then
        if printf '%s\n' "$pdic_port" > "$pdic_driver/bind"; then
            echo "Driver rebound to $pdic_port." | tee -a "$log_file"
        else
            echo "Driver rebind failed for $pdic_port; reboot to restore it." | tee -a "$log_file"
            rc=1
        fi
    fi
    [[ ! -f $log_file ]] || sync "$log_file" || true
    echo "Settings restored; log: $log_file"
    exit "$rc"
}
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
snapshot() {
    date --iso-8601=seconds
    uname -r
    cat /proc/sys/kernel/random/boot_id
    echo "Charger port: $pdic_port"
    if [[ -L /sys/bus/i2c/devices/$pdic_port/driver ]]; then
        echo "PDIC driver: $(readlink /sys/bus/i2c/devices/$pdic_port/driver)"
    else
        echo 'PDIC driver: unbound'
    fi
    for p in /sys/power/pm_test /sys/power/pm_async /sys/module/suspend/parameters/pm_test_delay /sys/class/power_supply/*/uevent /sys/power/suspend_stats/*; do
        [[ -f $p ]] || continue
        printf '\n%s\n' "$p"
        cat "$p"
    done
}
[[ -L /sys/bus/i2c/devices/$pdic_port/driver ]] || { echo "Driver not bound to $pdic_port; stopping."; exit 1; }
if strings "$(modinfo -n samsung-emuec)" | grep -q 'pm: quiesced'; then
    echo 'samsung-emuec on disk: 0004 (quiesce across sleep)'
else
    echo 'samsung-emuec on disk: without 0004 (expect the known reset in unplug mode)'
fi
battery_state=$(cat /sys/class/power_supply/samsung-galaxybook-battery/status)
echo "External power detected; battery: $battery_state."
printf '1\n' > /sys/power/pm_debug_messages
printf 'none\n' > /sys/power/pm_test
[[ $(cat /sys/power/pm_test) == *'[none]'* ]] || { echo 'PM test mode must be none; stopping.'; exit 1; }
{
    echo "Mode: $mode; real s2idle via direct kernel suspend, charger-port driver bound, bypassing systemd sleep hooks."
    echo BEFORE
    snapshot
} >> "$log_file"
echo "Log: $log_file"
echo 'Follow the timed control/unplug instructions above; briefly press the power button to wake.'
sync
echo 'Starting now.'
printf '<6>book4-pm-test: s2idle-bound %s begin\n' "$mode" > /dev/kmsg
rc=0
printf 'mem\n' > /sys/power/state || rc=$?
printf '<6>book4-pm-test: s2idle-bound %s returned rc=%s\n' "$mode" "$rc" > /dev/kmsg
{
    echo "AFTER: kernel suspend write returned $rc"
    snapshot
    echo 'KERNEL LOG'
    dmesg --color=never | tail -n 220
} >> "$log_file"
sync "$log_file"
echo "Kernel suspend returned (status $rc). Charger online: $(cat "$ac")."
echo 'Watching 90 s for a delayed reset; leave the machine alone.'
for t in 30 60 90; do
    sleep 30
    { echo "WATCH +${t}s"; snapshot; } >> "$log_file"
    sync "$log_file"
    echo "  +${t}s: still running; AC $(cat "$ac"), battery $(cat /sys/class/power_supply/samsung-galaxybook-battery/status)"
done
echo 'No delayed reset within 90 s.'
exit "$rc"
