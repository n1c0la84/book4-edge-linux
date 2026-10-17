#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Add Windows' system-level idle state ("platform.DRIPS" in the DSDT's
# \_SB.SYSM._LPI) to psci/power-domain-system, which has no idle state in our
# DT, so Linux never asks PSCI for a system-level state and the RSC never
# flushes the RPMh sleep votes.
#
# PSCI parameter = system 0x02000000|0xC300 | cluster CL5 0x50 | core C4 0x4.
# Latencies from the same _LPI entry: wake 5000 us, min residency 9000 us.
#
#   bash tools/power/drips-dtb.sh IN.dtb OUT.dtb [PARAM WAKE_US MIN_RES_US NAME]
#
# The other system states in the same _LPI, for experiments: SS1
# 0x02000154 500 7500 ss1, SS2 0x02000254 3000 8000 ss2 (entry/exit latency
# are split 2:3 from the _LPI wake latency).
set -euo pipefail
in=${1:?IN.dtb}; out=${2:?OUT.dtb}
param=${3:-0x0200c354}; wake=${4:-5000}; minres=${5:-9000}; sname=${6:-drips}
entry=$((wake * 2 / 5)); exit_=$((wake - entry))
n=/cpus/domain-idle-states/system-sleep-0

max=$(dtc -I dtb -O dts "$in" 2>/dev/null | grep -oE 'phandle = <0x[0-9a-f]+>' |
      grep -oE '0x[0-9a-f]+' | while read -r h; do echo $((h)); done | sort -n | tail -1)
ph=$((max + 1))

tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
cp "$in" "$tmp"
fdtput -c "$tmp" $n
fdtput -t s "$tmp" $n compatible domain-idle-state
fdtput -t s "$tmp" $n idle-state-name "$sname"
fdtput -t x "$tmp" $n arm,psci-suspend-param "$param"
fdtput -t u "$tmp" $n entry-latency-us $entry
fdtput -t u "$tmp" $n exit-latency-us $exit_
fdtput -t u "$tmp" $n min-residency-us $minres
fdtput -t u "$tmp" $n phandle $ph
fdtput -t u "$tmp" /psci/power-domain-system domain-idle-states $ph
dtc -q -I dtb -O dtb -p 8192 -o "$out" "$tmp"   # padded for GRUB
echo "wrote $out (system-sleep-0 $sname $param, $entry/$exit_/$minres us, phandle $ph)"
