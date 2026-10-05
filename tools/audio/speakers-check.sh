#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# After install/update-audio.sh: play a tone ladder through the "Speakers"
# crossover sink and show the four amplifiers' state while it plays.
# Run as your user.
set -u
CARD=$(aplay -l 2>/dev/null | awk -F'[ :]' '/GalaxyBook4Edge/{print $2; exit}')
G() { amixer -D "hw:$CARD" cget "name=$1" 2>/dev/null | awk -F= '/: values/{print $2}'; }
T=$(mktemp -d)
python3 - "$T" <<'PYEOF'
import math, struct, sys, wave
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
echo "== sinks"; wpctl status | sed -n '/Sinks:/,/Sources:/p' | head -8
pw-play --target book4_speakers "$T/ladder.wav" &
sleep 2
echo "== amplifiers while playing (DAC / PA)"
for a in SpkrRight SpkrLeft TweeterLeft TweeterRight; do
    printf '  %-11s DAC=%-4s PA=%s\n' "$a" "$(G "$a DAC Switch")" "$(G "$a PA Volume")"
done
wait
rm -rf "$T"
echo "Six rising tones: low ones from the woofers only, the last two (3 and 8 kHz)"
echo "noticeably brighter than before, from both slits."
