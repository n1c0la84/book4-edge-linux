#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# First llama.cpp run on the NPU with dspsignal (sleep-backport 0041 + the
# patched libcdsprpc in ~/npu/rt, tools/npu/fastrpc-patches). Run as yourself
# right after a fresh boot, with nothing unsaved:
#
#   bash tools/npu/dspsignal-test.sh
#
# A hung NPU run is followed by a hard reset minutes later (docs/TODO.md):
# if this says HUNG, reboot at once.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
npu=${NPU_ROOT:-$HOME/npu}
model=${MODEL:-$HOME/models/Llama-3.2-1B-Instruct-Q4_0.gguf}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

[ -e /dev/kvm ] || echo "warning: not the EL2 boot" >&2
[ "$(cat /proc/sys/kernel/tainted)" = 12288 ] ||
    echo "warning: kernel tainted $(cat /proc/sys/kernel/tainted) (12288 = our out-of-tree modules only); better reboot first" >&2

echo "== capabilities"
gcc -o "$work/caps" "$here/dspsignal-caps.c" -I "$npu/rt/include/fastrpc" \
    -L "$npu/rt/lib" -Wl,-rpath,"$npu/rt/lib" -lcdsprpc || exit 1
if ! "$work/caps"; then
    echo "dspsignal not on both sides: is the new kernel running, libcdsprpc rebuilt? Not running llama.cpp."
    exit 1
fi

echo "== llama.cpp on HTP0 (60 s limit)"
since=$(date '+%Y-%m-%d %H:%M:%S')
source "$HOME/src/ext/x1e-npu/scripts/env.sh"
unset DSPQUEUE_FORCE_V1
timeout -s INT 60 llama-completion -m "$model" --device HTP0 -ngl 99 -t 2 -n 32 -no-cnv \
    -p "The three primary colours are" > "$npu/dspsignal-run.log" 2>&1
rc=$?
grep -E 'primary|eval time' "$npu/dspsignal-run.log" | sed 's/^/   /'
echo "== DSP and driver messages"
journalctl --since "$since" --no-pager -o cat |
    grep -iE 'dspsignal|Queue Monitor|driver signal|dspqueue.*(error|fail)|No context ID|fastrpc.*(err|fail)' |
    grep -v wait_signal_locked | head -20
if [ $rc = 124 ]; then
    echo "HUNG (stopped after 60 s): reboot now, before anything else."
    exit 1
fi
echo "exit $rc (log: $npu/dspsignal-run.log)"
