#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Read-only dump of the kernel's clock, power-domain, regulator and
# interconnect state from debugfs (what is on, who votes what), plus the
# Qualcomm SoC sleep counters. Changes nothing.
#
#   bash tools/power/power-dump.sh [LABEL]       (default label: awake)
#
# Output: ${BOOK4_POWER_OUT:-~/src/book4-acpi}/linux-state/LABEL-TIME/
# Unused-but-on clocks: enable count 0 with hardware enable Y in clk_summary.
set -euo pipefail
label=${1:-awake}
out=${BOOK4_POWER_OUT:-$HOME/src/book4-acpi}/linux-state/$label-$(date +%Y%m%d-%H%M%S)
mkdir -p "$out"
dbg=/sys/kernel/debug

grab() { # grab <debugfs path> <file name>
    if sudo test -e "$dbg/$1"; then
        sudo cat "$dbg/$1" > "$out/$2" 2>/dev/null || echo "(read error)" > "$out/$2"
    else
        echo "(not present)" > "$out/$2"
    fi
}

sudo mountpoint -q $dbg || { echo "error: debugfs is not mounted at $dbg" >&2; exit 1; }
grab clk/clk_summary                   clk_summary.txt
grab pm_genpd/pm_genpd_summary         genpd_summary.txt
grab regulator/regulator_summary       regulator_summary.txt
grab interconnect/interconnect_summary interconnect_summary.txt
grab wakeup_sources                    wakeup_sources.txt
grab pm_genpd/power-domain-system/idle_states genpd_system_idle_states.txt
for f in $(sudo ls $dbg/qcom_stats 2>/dev/null); do grab qcom_stats/$f qcom_stats-$f.txt; done
# Providers whose sync_state never ran keep the firmware's boot votes.
for f in $(find /sys/devices -name state_synced 2>/dev/null); do
    echo "$(cat "$f") $(basename "$(dirname "$f")")"
done > "$out/state_synced.txt"
cat /proc/cmdline > "$out/cmdline.txt"
uname -r > "$out/uname.txt"
echo "Saved to $out:"
ls "$out"
