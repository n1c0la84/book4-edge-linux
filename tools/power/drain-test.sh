#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Suspend drain measured from the battery itself. Unplug the charger first,
# run this, close the lid for at least 30 minutes, then open it.
# Run as your user.
set -u
B=$(ls -d /sys/class/power_supply/*battery* | head -1)
OUT=~/drain-test-$(uname -r)-$(date +%H%M).txt
r() { echo "$(date +%s) $(cat $B/charge_now) $(cat $B/voltage_now) $(cat $B/capacity)"; }

[ "$(cat $B/status)" = Charging ] || [ "$(cat $B/status)" = Full ] && \
    { echo "Unplug the charger first."; exit 1; }
read -r t0 c0 v0 p0 < <(r)
echo "Start: $p0 %, $((c0/1000)) mAh. Close the lid now; open it after 30+ minutes."
n=$(cat /sys/power/suspend_stats/success)
while [ "$(cat /sys/power/suspend_stats/success)" = "$n" ]; do sleep 2; done
sleep 10
read -r t1 c1 v1 p1 < <(r)
python3 - "$t0" "$c0" "$v0" "$p0" "$t1" "$c1" "$v1" "$p1" "$(uname -r)" "$XDG_SESSION_DESKTOP" <<'EOF' | tee "$OUT"
import sys
t0,c0,v0,p0,t1,c1,v1,p1=map(int,sys.argv[1:9])
h=(t1-t0)/3600; mah=(c0-c1)/1000; v=(v0+v1)/2e6
print(f"kernel {sys.argv[9]}, desktop {sys.argv[10]}")
print(f"{h:.2f} h: {p0} % -> {p1} %, {mah:.0f} mAh used")
if h > 0: print(f"average {mah/h:.0f} mA = {mah/h*v/1000:.2f} W")
EOF
echo "saved to $OUT"
