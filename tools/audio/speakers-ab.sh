#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# A/B test on the shared-ports four-speaker DTB, with a fresh stream per state:
# for each amplifier pair, play 2 s of a low 250 Hz tone (woofers) and 2 s of
# a high 6 kHz tone (tweeters), quietly, through PipeWire.
#   A = original pair only, B = new pair only, C = all four
# Run as your user; stop other audio first.
set -u
CARD=$(aplay -l 2>/dev/null | awk -F'[ :]' '/GalaxyBook4Edge/{print $2; exit}')
SINK=alsa_output.platform-sound.HiFi__Speaker__sink
A() { amixer -q -D "hw:$CARD" cset "name=$1" "$2"; }
G() { amixer -D "hw:$CARD" cget "name=$1" | awk -F= '/: values/{print $2}'; }
T=$(mktemp -d)
python3 - "$T" <<'PYEOF'
import math, struct, sys, wave
# a ladder: 150, 300, 600, 1200, 3000, 8000 Hz, 1 s each, 0.3 s gaps
with wave.open(f"{sys.argv[1]}/ladder.wav", "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
    b = bytearray()
    for f in (150, 300, 600, 1200, 3000, 8000):
        for i in range(48000):
            fade = min(1, i / 2400, (48000 - i) / 2400)
            s = int(9000 * fade * math.sin(2 * math.pi * f * i / 48000))
            b += struct.pack("<2h", s, s)
        b += bytes(4 * 14400)
    w.writeframes(bytes(b))
PYEOF
pactl set-default-sink "$SINK"
old=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5
for a in SpkrLeft2 SpkrRight2; do
    A "$a COMP Switch" 1; A "$a BOOST Switch" 1; A "$a VISENSE Switch" 0
    A "$a WSA MODE" 0; A "$a PA Volume" 3
done
pair() {
    A "SpkrLeft DAC Switch" $1; A "SpkrRight DAC Switch" $1
    A "SpkrLeft2 DAC Switch" $2; A "SpkrRight2 DAC Switch" $2
}
: > ~/speakers-ab-result.txt
for step in "A 1 0 original pair only" "B 0 1 new pair only" "C 1 1 all four"; do
    set -- $step; tag=$1; o=$2; n=$3; shift 3
    pair $o $n
    echo "[$tag] $*  (DAC: Left=$(G 'SpkrLeft DAC Switch') Right=$(G 'SpkrRight DAC Switch') Left2=$(G 'SpkrLeft2 DAC Switch') Right2=$(G 'SpkrRight2 DAC Switch'))"
    read -rp "   Enter: six rising tones (150, 300, 600, 1200, 3000, 8000 Hz)... " _
    pw-play --target "$SINK" "$T/ladder.wav"
    read -rp "   Which tones did you hear (e.g. from the 3rd on, all, none)? " d
    echo "$tag ($*): $d" >> ~/speakers-ab-result.txt
done
pair 1 1
[ -n "${old:-}" ] && wpctl set-volume @DEFAULT_AUDIO_SINK@ "$old"
rm -rf "$T"
echo; cat ~/speakers-ab-result.txt
