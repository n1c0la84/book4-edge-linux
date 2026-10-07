#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Does the battery really charge after a plug-in? Waits for the charger to
# come online (plug it in while awake, or with the lid closed: the script
# carries on after the resume), then records for MINUTES the PD contract the
# kernel logged and the battery every 10 s, and sums up: capacity and charge
# gained, average power into the battery, and whether the EC's readings froze
# (voltage identical for a minute or more, as seen on 6 October).
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
start_cap=$(cat $B/capacity)
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
end=$(( t0 + MIN * 60 ))
while (( $(date +%s) < end )); do
    printf '%s %s %s %s %s %s %s %s\n' "$(date +%T)" "$(cat $B/capacity)" "$(cat $B/charge_now)" \
        "$(cat $B/current_now)" "$(cat $B/voltage_now)" "$(cat $B/status)" \
        "$(cat /sys/class/power_supply/1-0033-usb/online)" "$(cat /sys/class/power_supply/3-0033-usb/online)" >> "$LOG"
    sleep 10
done

python3 - "$LOG" <<'PY' | tee -a "$LOG"
import sys
rows = [l.split() for l in open(sys.argv[1]) if l[0].isdigit()]
cap = [int(r[1]) for r in rows]; chg = [int(r[2]) for r in rows]
cur = [int(r[3]) for r in rows]; volt = [int(r[4]) for r in rows]
same = longest = 1
for a, b in zip(volt, volt[1:]):
    same = same + 1 if a == b else 1
    longest = max(longest, same)
avg_w = sum(c * v for c, v in zip(cur, volt)) / len(rows) / 1e12
print(f"# RESULT capacity {cap[0]} -> {cap[-1]} %  charge +{(chg[-1] - chg[0]) / 1000:.0f} mAh  "
      f"avg into battery {avg_w:.1f} W  readings frozen: "
      f"{'YES, ' + str(longest * 10) + ' s unchanged' if longest >= 6 else 'no'}")
PY
