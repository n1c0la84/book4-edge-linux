#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Trace every interconnect vote (icc_set_bw) and driver PM callback across one
# pm_test=devices suspend cycle, to see what a driver votes, and when,
# relative to its resume. Only the trace buffer is touched.
#
#   bash tools/power/icc-trace.sh [DEV]     (default DEV: 1d84000.ufshc)
#
# Full trace: ${BOOK4_POWER_OUT:-~/src/book4-acpi}/linux-state/icc-trace-TIME.txt
# Note: pm_test=devices skips the late/noirq phases (e.g. qcom-pcie's).
set -euo pipefail
dev=${1:-1d84000.ufshc}
T=/sys/kernel/tracing
out=${BOOK4_POWER_OUT:-$HOME/src/book4-acpi}/linux-state/icc-trace-$(date +%H%M%S).txt
mkdir -p "$(dirname "$out")"
sudo -v
sudo test -d $T/events/interconnect || { echo "no interconnect tracepoints in this kernel" >&2; exit 1; }
sudo sh -c "echo 0 > $T/tracing_on; echo > $T/trace; echo 8192 > $T/buffer_size_kb
    echo 1 > $T/events/interconnect/icc_set_bw/enable
    echo 1 > $T/events/interconnect/icc_set_bw_end/enable
    echo 1 > $T/events/power/device_pm_callback_start/enable 2>/dev/null || true
    echo 1 > $T/tracing_on"
echo "== suspend cycle (pm_test=devices) ..."
sudo sh -c 'echo devices > /sys/power/pm_test; echo mem > /sys/power/state; echo none > /sys/power/pm_test'
sudo sh -c "echo 0 > $T/tracing_on; echo 0 > $T/events/enable"
sudo cat $T/trace > "$out"
echo "== saved $out ($(wc -l < "$out") lines)"
echo "== votes by $dev and its PM callbacks, in order:"
grep -E "icc_set_bw: .*dev=$dev|device_pm_callback_start: .*$dev" "$out" |
    sed -E 's/^ *\S+ +\[[0-9]+\] \S+ +//; s/path=([a-z0-9_]+)@[^ ]*-([a-z0-9_]+)@\S+/path=\1->\2/' | cut -c1-200 | tail -60
