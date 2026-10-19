#!/usr/bin/env bash
# On the "test: el2-drips" boot: are leftover EL1 timers pending at EL2?
#  1. build tools/power/timer-check/timer_check.ko if needed (Fedora container)
#  2. load it read-only: print every CPU's timer control registers
#  3. load it again with disable=1 (EL1 virtual/physical timers off)
#  4. one suspend with the probe (wake it after ~30 s)
# Run as yourself: bash ~/timer-test.sh
set -euo pipefail
d=$HOME/Projects/book4-edge-linux/tools/power/timer-check
grep -q 'id_aa64mmfr0.ecv' /proc/cmdline || { echo "error: boot an EL2 entry (test: el2-drips)" >&2; exit 1; }
[ -e $d/timer_check.ko ] || bash $d/build.sh
sudo -v
sudo rmmod timer_check 2>/dev/null || true
sudo insmod $d/timer_check.ko
sudo dmesg | grep 'timer_check:' | tail -13
sudo rmmod timer_check
sudo insmod $d/timer_check.ko disable=1
sudo dmesg | grep 'timer_check:' | tail -1
bash ~/el2-probe.sh
