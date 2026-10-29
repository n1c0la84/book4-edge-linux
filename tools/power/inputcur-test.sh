#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Is the awake charging stall the charger's input limit? Windows' EmuEC.sys
# tells the EC the adapter's limit after every PD contract (EC extended
# commands 0x90/0x91, docs/power.md "Why awake charging stalls"); Linux never
# does. This sends the same commands, in EmuEC.sys's own ramp, and records
# the battery current at idle before and after. Run plugged in, awake, idle,
# battery well below 80 %. Uses sudo for the EC (I2C) only.
#
#   bash tools/power/inputcur-test.sh [FINAL_MA] [WATTS] [MV]    default 3000 65 20000
set -euo pipefail
FINAL=${1:-3000}; WATTS=${2:-65}; MV=${3:-20000}
B=/sys/class/power_supply/samsung-galaxybook-battery
EC="$(dirname "$(readlink -f "$0")")/../ec/ectool.py"
LOG=$HOME/inputcur-test-$(date +%Y%m%d-%H%M).log

[ "$(cat /sys/class/power_supply/samsung-galaxybook-ac/online)" = 1 ] || { echo "Plug the charger in first." >&2; exit 1; }
sudo -v

sample() { # sample LABEL SECONDS: battery current every 3 s
    local label=$1 n=$(( $2 / 3 )) i
    for (( i = 0; i < n; i++ )); do
        printf '%s %-6s %8s uA  %s uV  %s %%\n' "$(date +%T)" "$label" \
            "$(cat $B/current_now)" "$(cat $B/voltage_now)" "$(cat $B/capacity)"
        sleep 3
    done | tee -a "$LOG"
}

{
    echo "# $(date '+%F %T'), kernel $(uname -r), final $FINAL mA, adapter $WATTS W $MV mV"
    journalctl -k --no-pager -b | grep -E 'emuec.*PD contract' | tail -3 | sed 's/^/# /' || true
} | tee "$LOG"
sample before 45
for ma in 490 1300 "$FINAL"; do   # EmuEC.sys: 490, 1300 mA 200 ms apart, then the limit
    sudo python3 "$EC" inputcur "$ma" "$WATTS" "$MV" | tee -a "$LOG"
    [ "$ma" = "$FINAL" ] || sleep 0.2
done
sample after 90
awk '$2 == "before" { b += $3; nb++ } $2 == "after" { a += $3; na++ }
     END { printf "# RESULT: idle battery current before %.0f mA, after %.0f mA\n", b / nb / 1000, a / na / 1000 }' \
    "$LOG" | tee -a "$LOG"
echo "Log: $LOG"
