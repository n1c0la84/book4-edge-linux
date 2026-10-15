#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# One bisect round for "which interconnect vote does resume need": hold peak
# votes on chosen DT nodes' interconnect paths with icc_hold.ko, force the
# interconnect sync (the firmware's boot-time floors go away for good), then
# run suspend-check.sh. Rounds can follow each other in one boot: swapping the
# held set recreates the test condition. Reboot only after a failed round.
#
#   bash tools/power/icc-hold-test.sh all=1
#   bash tools/power/icc-hold-test.sh nodes=/soc@0/ufshc@1d84000 [index=N] [tag=3]
#
# Build the module first: bash tools/power/icc-hold/build.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
ko=$here/icc-hold/icc_hold.ko
[ $# -ge 1 ] || { sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[ -e "$ko" ] || { echo "error: $ko missing; run tools/power/icc-hold/build.sh" >&2; exit 1; }
sudo -v
if grep -q '^icc_hold ' /proc/modules; then sudo rmmod icc_hold && echo "released the previous round's votes"; fi
sudo insmod "$ko" "$@"
sudo dmesg | grep 'icc_hold: holding [0-9]* paths' | tail -1
for p in $(find /sys/devices -path '*interconnect*' -name state_synced 2>/dev/null); do
    [ "$(cat "$p")" = 1 ] || printf 1 | sudo tee "$p" >/dev/null   # exactly "1": no newline
done
echo "interconnect providers not synced: $(for p in $(find /sys/devices -path '*interconnect*' -name state_synced); do [ "$(cat $p)" = 1 ] || basename "$(dirname $p)"; done | tr '\n' ' ')"
bash "$here/suspend-check.sh"
