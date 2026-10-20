#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Battery drain over one real suspend, plus the deep-sleep evidence: the
# Qualcomm SoC sleep counters (aosd/cxsd/ddr) and how often the PSCI system
# power domain was entered in s2idle. Like drain-test.sh, but logged.
# On battery; wake the machine yourself after 30+ minutes (an hour is better):
#
#   bash tools/power/sleep-drain.sh [LABEL]
#
# Appends to ${BOOK4_POWER_OUT:-~/src/book4-acpi}/linux-state/sleep-drain.log
set -euo pipefail
label=${1:-test}
bat=/sys/class/power_supply/samsung-galaxybook-battery
log=${BOOK4_POWER_OUT:-$HOME/src/book4-acpi}/linux-state/sleep-drain.log
stats=/sys/kernel/debug/qcom_stats
sysd=/sys/kernel/debug/pm_genpd/power-domain-system/idle_states
mkdir -p "$(dirname "$log")"

[[ $(cat $bat/status) == Discharging ]] || { echo "error: unplug the charger first (status: $(cat $bat/status))" >&2; exit 1; }

counters() {
    for s in aosd cxsd ddr; do printf "%s=%s " $s "$(sudo awk '/^Count/{print $2}' $stats/$s)"; done
    printf "system-pd-s2idle=%s" "$(sudo awk 'NR>1 {n+=$NF} END {print n+0}' $sysd 2>/dev/null)"
}

sudo -v   # ask for the password now, not after resume
c0=$(cat $bat/charge_now); t0=$(date +%s); s0=$(counters)
echo "before: charge ${c0} uAh, $(cat $bat/capacity) %, counters: $s0"
echo "suspending in 5 s ..."
sleep 5
ok0=$(cat /sys/power/suspend_stats/success); fail0=$(cat /sys/power/suspend_stats/fail)
systemctl suspend              # returns before the suspend starts: wait for the kernel's count
while [ "$(cat /sys/power/suspend_stats/success)" = "$ok0" ] && [ "$(cat /sys/power/suspend_stats/fail)" = "$fail0" ]; do sleep 1; done
[ "$(cat /sys/power/suspend_stats/fail)" = "$fail0" ] || echo "warning: the suspend FAILED (see dmesg)"
sleep 3                        # let resume finish
# The EC refreshes charge_now late after resume (over a minute on 20 October,
# then a jump of 70 mAh) and in steps of about 1 % (35 mAh): wait for the
# value to change (at most 3 min), and count on long sleeps for precision.
echo "resumed; waiting for the EC's battery reading to change (up to 3 min) ..."
i=0
while [ "$(cat $bat/charge_now)" = "$c0" ] && [ $i -lt 180 ]; do sleep 5; i=$((i + 5)); done
[ "$(cat $bat/charge_now)" != "$c0" ] || echo "warning: charge_now never changed: the figure below is not a measurement"
sudo -v
c1=$(cat $bat/charge_now); t1=$(date +%s); s1=$(counters)
v=$(cat $bat/voltage_now)

python3 -I - "$label" "$c0" "$c1" "$t0" "$t1" "$v" "$s0" "$s1" "$(cat /proc/cmdline)" <<'EOF' | tee -a "$log"
import sys, time
label, c0, c1, t0, t1, v, s0, s1, cmd = sys.argv[1:]
c0, c1, t0, t1, v = int(c0), int(c1), int(t0), int(t1), int(v)
h = (t1 - t0 - 38) / 3600          # minus the 5 s + 3 s + 30 s spent awake
mah = (c0 - c1) / 1000
flags = " ".join(w for w in cmd.split()
                 if w in ("clk_ignore_unused", "pd_ignore_unused") or w.startswith("fw_devlink")) or "none"
print(f"{time.strftime('%F %H:%M')} [{label}] flags: {flags}")
print(f"  slept {h*60:.0f} min, used {mah:.0f} mAh = {mah/h:.0f} mA = {mah/h*v/1e9:.2f} W"
      f" ({(c0-c1)/36000/h:.1f} %/h of a full 3600 mAh)")
print(f"  counters before: {s0}\n  counters after:  {s1}")
EOF
