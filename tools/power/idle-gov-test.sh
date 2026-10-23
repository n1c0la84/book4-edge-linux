#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Compare cpuidle governors while the machine is in normal use: switch to
# GOVERNOR, wait MINUTES (use the machine as usual meanwhile, but don't let it
# sleep), then report for that period only, per CPU cluster: the share of
# time in CL4/CL5 and how many entries ended before the state's minimum
# residency ("woken too early": the governor's misses), plus the average
# battery power if on battery. Puts the previous governor back at the end.
# teo needs CONFIG_CPU_IDLE_GOV_TEO (sleep kernel builds since 23 October).
#
# Run as yourself:  bash tools/power/idle-gov-test.sh GOVERNOR [MINUTES]
#   e.g. teo 15, then menu 15 doing about the same things.
set -euo pipefail
gov=${1:?usage: idle-gov-test.sh GOVERNOR [MINUTES]}; min=${2:-15}
cpuidle=/sys/devices/system/cpu/cpuidle
bat=/sys/class/power_supply/samsung-galaxybook-battery
grep -qw "$gov" $cpuidle/available_governors ||
    { echo "error: '$gov' not built in (available: $(cat $cpuidle/available_governors))" >&2; exit 1; }
sudo -v
prev=$(cat $cpuidle/current_governor)
snap() { for c in 0 1 2; do sudo awk -v c=$c 'NR > 1 { print c, $1, $2, $3, $5 }' /sys/kernel/debug/pm_genpd/power-domain-cpu-cluster$c/idle_states; done; }
echo "$gov" | sudo tee $cpuidle/current_governor >/dev/null
trap 'echo "$prev" | sudo tee $cpuidle/current_governor >/dev/null; echo "governor back to $prev"' EXIT
echo "governor: $gov for $min min (keep the machine awake; use it normally)"
a=$(snap); t0=$(date +%s); c0=$(cat $bat/charge_now); s0=$(cat $bat/status)
systemd-inhibit --what=sleep:handle-lid-switch --why="idle governor test" sleep $((min * 60))
b=$(snap); t1=$(date +%s); c1=$(cat $bat/charge_now); s1=$(cat $bat/status)
secs=$((t1 - t0))
echo "== $gov, $((secs / 60)) min"
join -j1 <(echo "$a" | awk '{print $1"/"$2, $3, $4, $5}' | sort) <(echo "$b" | awk '{print $1"/"$2, $3, $4, $5}' | sort) |
    awk -v s=$secs '{ split($1, k, "/"); dt = ($5 - $2) / 1000; du = $6 - $3; da = $7 - $4;
        printf "   cluster%s %s (%s): %5.1f %% of the time, %6d entries, %3.0f %% woken too early\n",
               k[1], k[2], (k[2] == "S0" ? "CL4" : "CL5"), 100 * dt / s, du, (du ? 100 * da / du : 0) }'
if [ "$s0" = Discharging ] && [ "$s1" = Discharging ]; then
    awk -v c=$((c0 - c1)) -v v="$(cat $bat/voltage_now)" -v s=$secs \
        'BEGIN { printf "   battery: %.0f mAh = %.2f W average\n", c / 1000, c / 1e6 * v / 1e6 / (s / 3600) }'
fi
