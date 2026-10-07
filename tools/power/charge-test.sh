#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Does the battery really charge after a plug-in? Waits for the charger to
# come online (plug it in while awake, or with the lid closed: the script
# carries on after the resume), records the PD contract the kernel logged,
# waits MINUTES, then asks you to unplug and reads the battery again.
# The EC does not refresh the battery values while a charger is connected
# (they stay identical to the microvolt, 6-7 October); they refresh at the
# plug and unplug events, so the gain is measured before plug-in vs. after
# unplug, not from the live readings.
# No root needed. Run with the charger unplugged; battery well below 80 %
# (charging slows down near full anyway).
#
#   bash tools/power/charge-test.sh LABEL [MINUTES]     e.g. awake-60w 15
set -euo pipefail
LABEL=${1:?usage: $0 LABEL [MINUTES]   (e.g. awake-60w, asleep-65w)}
MIN=${2:-15}
B=/sys/class/power_supply/samsung-galaxybook-battery
AC=/sys/class/power_supply/samsung-galaxybook-ac
LOG=$HOME/charge-test-$LABEL-$(date +%Y%m%d-%H%M).log

[ "$(cat $AC/online)" = 0 ] || { echo "Unplug the charger first, then start this again." >&2; exit 1; }
start_cap=$(cat $B/capacity); start_chg=$(cat $B/charge_now)
(( start_cap < 80 )) || echo "Note: battery at $start_cap %: above ~80 % charging is slow anyway."
echo "Waiting for the charger ($LABEL). Plug it in now (or close the lid, plug in, open it after a minute)."
mark=$(date '+%Y-%m-%d %H:%M:%S')
until [ "$(cat $AC/online)" = 1 ]; do sleep 1; done
t0=$(date +%s)
echo "Charger online at $(date +%T); recording $MIN minutes into $LOG"
sleep 5   # let the contract and the EC settle

{
    echo "# $LABEL, plugged in $(date -d @$t0 '+%F %T'), kernel $(uname -r)"
    echo "# PD contract lines since the start:"
    journalctl -k --no-pager -o short-iso --since "$mark" | grep -E 'emuec.*(PD contract|pm:)' | sed 's/^/#   /' || true
    echo "# time  capacity  charge_uAh  current_uA  voltage_uV  status  port1 port3"
} > "$LOG"
echo "# before: $start_cap % $start_chg uAh" >> "$LOG"
end=$(( t0 + MIN * 60 ))
while (( $(date +%s) < end )); do
    printf '%s %s %s %s %s %s %s %s\n' "$(date +%T)" "$(cat $B/capacity)" "$(cat $B/charge_now)" \
        "$(cat $B/current_now)" "$(cat $B/voltage_now)" "$(cat $B/status)" \
        "$(cat /sys/class/power_supply/1-0033-usb/online)" "$(cat /sys/class/power_supply/3-0033-usb/online)" >> "$LOG"
    sleep 10
done

echo
echo "Time is up: UNPLUG the charger now."
until [ "$(cat $AC/online)" = 0 ]; do sleep 1; done
sleep 30   # let the EC refresh the battery values
end_cap=$(cat $B/capacity); end_chg=$(cat $B/charge_now)
mins=$(( ($(date +%s) - t0) / 60 ))
awk -v c0="$start_cap" -v c1="$end_cap" -v q0="$start_chg" -v q1="$end_chg" -v v="$(cat $B/voltage_now)" -v m="$mins" \
    'BEGIN { wh = (q1 - q0) / 1e6 * v / 1e6; printf "# RESULT %s: capacity %d -> %d %%, charge %+d mAh, about %.1f Wh in %d min = %.1f W into the battery\n", "'"$LABEL"'", c0, c1, (q1 - q0) / 1000, wh, m, (m ? wh * 60 / m : 0) }' | tee -a "$LOG"
