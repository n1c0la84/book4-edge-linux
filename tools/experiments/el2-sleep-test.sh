#!/usr/bin/env bash
# On "test: el2-sleep": the x1e-sleep recipe (book4s kernel at EL2, el1tmr
# programs the EL1 physical timer with the next deadline before power-down
# and clears the stray CNTV). One probe suspend, wake it after ~30 s.
# Run as yourself: bash ~/el2-sleep-test.sh
set -euo pipefail
[ "$(uname -r)" = 7.2.7-book4s ] || { echo "error: boot 'test: el2-sleep' (running $(uname -r))" >&2; exit 1; }
journalctl -k -b -o cat | grep -c 'All CPU(s) started at EL2' >/dev/null || { echo "error: not an EL2 boot" >&2; exit 1; }
sudo -v
l=$(journalctl -k -b -o cat | grep 'qcom-pdc: x1e' || true); echo "   ${l:-(no PDC mode line)}"
sudo modprobe el1tmr && echo "   el1tmr loaded"
bash ~/el2-probe.sh
