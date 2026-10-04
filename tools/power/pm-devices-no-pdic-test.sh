#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Repeat the devices test with only the charging port driver unbound.
# Experimental hardware diagnostic; see docs/power.md before running.
set -euo pipefail
mode=${1:-}
case "$mode" in control|unplug) ;; *) echo "Usage: sudo bash $0 control|unplug" >&2; exit 2;; esac
[[ $EUID -eq 0 ]] || { echo 'Run with sudo from a terminal.'; exit 1; }
[[ $(cat /sys/power/pm_test) == *'[none]'* ]] || { echo 'Another PM test is selected; stopping.'; exit 1; }
[[ $(cat /sys/power/mem_sleep) == *'[s2idle]'* ]] || { echo 'Expected s2idle; stopping.'; exit 1; }
ac=/sys/class/power_supply/samsung-galaxybook-ac/online
[[ $(cat "$ac") == 1 ]] || { echo 'Connect the charger, wait until detected, then run again.'; exit 1; }
echo 'Keep the lid open and save your work. Do not press the power button.'
if [[ $mode == control ]]; then
    echo 'CONTROL: keep the charger connected throughout.'
else
    echo 'UNPLUG: once the screen goes dark, wait 5 seconds, unplug, and leave unplugged.'
fi
echo 'The kernel will resume devices automatically after a 30-second pause.'
read -r -p 'Press Enter to start, or Ctrl-C to cancel. ' _
[[ $(cat "$ac") == 1 ]] || { echo 'Charger is no longer detected; stopping.'; exit 1; }
log_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
log_file="$log_dir/pm-devices-no-pdic-$mode-$(date +%Y%m%d-%H%M%S).log"
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
old_delay=$(cat /sys/module/suspend/parameters/pm_test_delay)
old_debug=$(cat /sys/power/pm_debug_messages)
restore() {
    local rc=$?
    trap - EXIT
    printf 'none\n' > /sys/power/pm_test || true
    printf '%s\n' "$old_delay" > /sys/module/suspend/parameters/pm_test_delay || true
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
{
    echo "Mode: $mode; temporarily unbind only charger port $pdic_port before the devices test."
    echo BEFORE_UNBIND
    snapshot
} > "$log_file"
sync "$log_file"
echo "Temporarily unbinding $pdic_port; keep the charger connected."
unbound=1
printf '%s\n' "$pdic_port" > "$pdic_driver/unbind"
[[ ! -L /sys/bus/i2c/devices/$pdic_port/driver ]] || { echo 'Driver still bound; stopping.'; exit 1; }
echo 'Waiting 10 seconds to verify external power remains detected.'
sleep 10
{
    echo AFTER_UNBIND
    snapshot
} >> "$log_file"
sync "$log_file"
battery_state=$(cat /sys/class/power_supply/samsung-galaxybook-battery/status)
if [[ $(cat "$ac") != 1 || ( $battery_state != Charging && $battery_state != Full ) ]]; then
    echo "External power check failed (battery: $battery_state); aborting without suspend."
    exit 1
fi
echo "External power detected; battery: $battery_state."
printf '30\n' > /sys/module/suspend/parameters/pm_test_delay
printf '1\n' > /sys/power/pm_debug_messages
printf 'devices\n' > /sys/power/pm_test
[[ $(cat /sys/power/pm_test) == *'[devices]'* ]] || { echo 'Failed to select devices test.'; exit 1; }
{
    echo "Mode: $mode; direct kernel PM test, charger-port driver unbound, bypassing systemd sleep hooks."
    echo BEFORE
    snapshot
} >> "$log_file"
echo "Log: $log_file"
echo 'Allow up to 90 seconds for the display to return.'
sync
echo 'Starting now.'
printf '<6>book4-pm-test: devices-no-pdic %s begin\n' "$mode" > /dev/kmsg
rc=0
printf 'mem\n' > /sys/power/state || rc=$?
printf '<6>book4-pm-test: devices-no-pdic %s returned rc=%s\n' "$mode" "$rc" > /dev/kmsg
{
    echo "AFTER: kernel suspend write returned $rc"
    snapshot
    echo 'KERNEL LOG'
    dmesg --color=never | tail -n 220
} >> "$log_file"
sync "$log_file"
echo "Kernel test returned (status $rc). Charger online: $(cat "$ac")."
exit "$rc"
