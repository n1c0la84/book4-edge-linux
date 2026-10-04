#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Freeze processes only; control/unplug comparison with a 30-second pause.
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
    echo 'UNPLUG: when TEST STARTING NOW appears, wait 5 seconds, unplug, and leave unplugged.'
fi
echo 'The desktop will unfreeze automatically after a 30-second pause; the display may stay on.'
read -r -p 'Press Enter to start, or Ctrl-C to cancel. ' _
[[ $(cat "$ac") == 1 ]] || { echo 'Charger is no longer detected; stopping.'; exit 1; }
log_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
log_file="$log_dir/pm-freezer-$mode-$(date +%Y%m%d-%H%M%S).log"
old_delay=$(cat /sys/module/suspend/parameters/pm_test_delay)
old_debug=$(cat /sys/power/pm_debug_messages)
restore() {
    local rc=$?
    trap - EXIT
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
    for p in /sys/power/pm_test /sys/module/suspend/parameters/pm_test_delay /sys/class/power_supply/*/uevent /sys/power/suspend_stats/*; do
        [[ -f $p ]] || continue
        printf '\n%s\n' "$p"
        cat "$p"
    done
}
printf '30\n' > /sys/module/suspend/parameters/pm_test_delay
printf '1\n' > /sys/power/pm_debug_messages
printf 'freezer\n' > /sys/power/pm_test
[[ $(cat /sys/power/pm_test) == *'[freezer]'* ]] || { echo 'Failed to select freezer test.'; exit 1; }
{
    echo "Mode: $mode; direct kernel PM test, bypassing systemd sleep hooks."
    echo BEFORE
    snapshot
} > "$log_file"
echo "Log: $log_file"
echo 'Allow up to 60 seconds for the desktop to respond again.'
sync
echo 'TEST STARTING NOW: follow the control/unplug instructions above.'
printf '<6>book4-pm-test: freezer %s begin\n' "$mode" > /dev/kmsg
rc=0
printf 'mem\n' > /sys/power/state || rc=$?
printf '<6>book4-pm-test: freezer %s returned rc=%s\n' "$mode" "$rc" > /dev/kmsg
{
    echo "AFTER: kernel suspend write returned $rc"
    snapshot
    echo 'KERNEL LOG'
    dmesg --color=never | tail -n 220
} >> "$log_file"
sync "$log_file"
echo "Kernel test returned (status $rc). Charger online: $(cat "$ac")."
exit "$rc"
