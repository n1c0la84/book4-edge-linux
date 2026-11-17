#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Everything that can hold the SoC awake, in one file per kernel, to diff a
# kernel that collapses CX in s2idle (7.2) against one that does not (7.3,
# 17 November): interconnect votes, enabled clocks, enabled regulators,
# power domains, loaded modules, devices without runtime suspend.
#
#   bash tools/power/vote-dump.sh          -> ~/vote-dump-$(uname -r).txt
#   then on the other kernel the same; diff the two files.
set -uo pipefail
out=$HOME/vote-dump-$(uname -r).txt
sudo -v || exit 1
{
echo "== $(uname -r) $(date)"
echo "== interconnect (nodes with a nonzero vote)"
sudo awk 'NR<=2 || $2!=0 || $3!=0' /sys/kernel/debug/interconnect/interconnect_summary 2>&1
echo "== clocks enabled (name enable_cnt prepare_cnt rate)"
sudo awk 'NR>3 && $2>0 {print $1, $2, $3, $5}' /sys/kernel/debug/clk/clk_summary 2>&1 | sort
echo "== regulators"
sudo cat /sys/kernel/debug/regulator/regulator_summary 2>&1
echo "== genpd"
sudo cat /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>&1
echo "== modules"
lsmod | awk 'NR>1 {print $1}' | sort
echo "== runtime-PM active devices"
for d in /sys/devices/platform/soc@0/*; do s=$(cat $d/power/runtime_status 2>/dev/null) && [ "$s" = active ] && echo "${d##*/}"; done
} > "$out" 2>&1
echo "Saved $out ($(wc -l < "$out") lines)."
