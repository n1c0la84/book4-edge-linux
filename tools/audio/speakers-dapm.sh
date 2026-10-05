#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# While a tone plays on one speaker channel, dump which audio path widgets
# (DAPM) are powered: WSA macros, their outputs and the four amplifiers.
# Usage: bash ~/speakers-dapm.sh [channel 1-4] (default 3). Run as your user.
set -u
CH=${1:-3}
SINK=alsa_output.platform-sound.HiFi__Speaker__sink
sudo -v
D=$(sudo sh -c 'ls -d /sys/kernel/debug/asoc/*/dapm 2>/dev/null' | head -1)
[ -n "$D" ] || { echo "no DAPM debugfs"; exit 1; }
OUT=~/speakers-dapm-ch$CH.txt
PIPEWIRE_NODE=$SINK speaker-test -D pipewire -c 4 -s "$CH" -t sine -f 1000 -l 3 >/dev/null 2>&1 &
sleep 2
{
echo "channel $CH playing; card dir $D"
C=${D%/dapm}
sudo sh -c "find $C -path '*/dapm/*' -type f 2>/dev/null" | while read -r f; do
    rel=${f#$C/}
    case "$rel" in *[Ww][Ss][Aa]*|*Spkr*|*SPK*|*AIF1*|*MultiMedia2*|*sdw*) ;; *) continue;; esac
    printf '%-60s %s\n' "$rel" "$(sudo head -1 "$f")"
done | sort
} > "$OUT" 2>&1
wait
echo "saved $OUT"
