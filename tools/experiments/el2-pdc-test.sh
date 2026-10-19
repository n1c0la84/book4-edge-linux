#!/usr/bin/env bash
# On "test: el2-pdc": PDC mode, then switch off the known EL2 artifact (the
# EL1 virtual timer left armed on CPU 0, timer_check disable=1), then one
# probe suspend (wake it after ~30 s). Run as yourself: bash ~/el2-pdc-test.sh
set -euo pipefail
p=$HOME/Projects/book4-edge-linux/tools/power
journalctl -k -b -o cat | grep -c 'All CPU(s) started at EL2' >/dev/null || { echo "error: not an EL2 boot" >&2; exit 1; }
journalctl -k -b -o cat | grep -E 'qcom-pdc' || echo "(no qcom-pdc line: not the pdc kernel?)"
[ -e $p/timer-check/timer_check.ko ] || bash $p/timer-check/build.sh
sudo -v
sudo rmmod timer_check 2>/dev/null || true
sudo insmod $p/timer-check/timer_check.ko disable=1
bash ~/el2-probe.sh
sudo rmmod timer_check
sudo dmesg | grep 'timer_check: [0-9]' | tail -1
