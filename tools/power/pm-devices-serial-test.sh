#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Repeat the devices test with parallel PM callbacks disabled.
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
log_file="$log_dir/pm-devices-serial-$mode-$(date +%Y%m%d-%H%M%S).log"
old_async=$(cat /sys/power/pm_async)
old_delay=$(cat /sys/module/suspend/parameters/pm_test_delay)
old_debug=$(cat /sys/power/pm_debug_messages)
restore() {
    local rc=$?
    trap - EXIT
    printf '%s\n' "$old_async" > /sys/power/pm_async || true
    printf 'none\n' > /sys/power/pm_test || true
    printf '%s\n' "$old_delay" > /sys/module/suspend/parameters/pm_test_delay || true
    printf '%s\n' "$old_debug" > /sys/power/pm_debug_messages || true
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
    for p in /sys/power/pm_test /sys/power/pm_async /sys/module/suspend/parameters/pm_test_delay /sys/class/power_supply/*/uevent /sys/power/suspend_stats/*; do
        [[ -f $p ]] || continue
        printf '\n%s\n' "$p"
        cat "$p"
    done
}
printf '0\n' > /sys/power/pm_async
[[ $(cat /sys/power/pm_async) == 0 ]] || { echo 'Failed to disable parallel PM callbacks.'; exit 1; }
printf '30\n' > /sys/module/suspend/parameters/pm_test_delay
printf '1\n' > /sys/power/pm_debug_messages
printf 'devices\n' > /sys/power/pm_test
[[ $(cat /sys/power/pm_test) == *'[devices]'* ]] || { echo 'Failed to select devices test.'; exit 1; }
{
    echo "Mode: $mode; direct kernel PM test, pm_async=0, bypassing systemd sleep hooks."
    echo BEFORE
    snapshot
} > "$log_file"
echo "Log: $log_file"
echo 'Allow up to 90 seconds for the display to return.'
sync
echo 'Starting now: PM callbacks will run sequentially.'
printf '<6>book4-pm-test: devices-serial %s begin\n' "$mode" > /dev/kmsg
rc=0
printf 'mem\n' > /sys/power/state || rc=$?
printf '<6>book4-pm-test: devices-serial %s returned rc=%s\n' "$mode" "$rc" > /dev/kmsg
{
    echo "AFTER: kernel suspend write returned $rc"
    snapshot
    echo 'KERNEL LOG'
    dmesg --color=never | tail -n 220
} >> "$log_file"
sync "$log_file"
echo "Kernel test returned (status $rc). Charger online: $(cat "$ac")."
exit "$rc"
