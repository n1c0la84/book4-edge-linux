#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# One amplifier at a time: all four PCM channels play a quiet 1 kHz tone,
# but only one amplifier's DAC is on. Tells which amplifiers make sound and
# where each one physically is. Raw (no PipeWire). Run as your user.
set -u
CARD=$(aplay -l 2>/dev/null | awk -F'[ :]' '/GalaxyBook4Edge/{print $2; exit}')
T=$(mktemp -d)
python3 - "$T" <<'PYEOF'
import math, struct, sys, wave
with wave.open(f"{sys.argv[1]}/all.wav", "wb") as w:
    w.setnchannels(4); w.setsampwidth(2); w.setframerate(48000)
    f = bytearray()
    for i in range(48000 * 3):
        s = int(4000 * math.sin(2 * math.pi * 1000 * i / 48000))
        f += struct.pack("<4h", s, s, s, s)
    w.writeframes(bytes(f))
PYEOF
systemctl --user stop pipewire.socket pipewire-pulse.socket pipewire wireplumber pipewire-pulse 2>/dev/null
sleep 1
A() { amixer -q -D "hw:$CARD" cset "name=$1" "$2"; }
A "WSA_CODEC_DMA_RX_0 Audio Mixer MultiMedia2" 1
for m in WSA WSA2; do
    A "$m WSA RX0 MUX" AIF1_PB; A "$m WSA RX1 MUX" AIF1_PB
    A "$m WSA_RX0 INP0" RX0;    A "$m WSA_RX1 INP0" RX1
    A "$m WSA_RX0 Digital Volume" 72; A "$m WSA_RX1 Digital Volume" 72
done
AMPS="SpkrLeft SpkrLeft2 SpkrRight SpkrRight2"
for a in $AMPS; do
    A "$a COMP Switch" 1; A "$a BOOST Switch" 1; A "$a DAC Switch" 0
    A "$a VISENSE Switch" 0; A "$a WSA MODE" 0; A "$a PA Volume" 3
done
: > ~/speakers-amps-result.txt
for a in $AMPS; do
    for b in $AMPS; do A "$b DAC Switch" 0; done
    A "$a DAC Switch" 1
    read -rp "Only $a on: press Enter for 3 s of tone... " _
    aplay -q -D "hw:$CARD,1" "$T/all.wav" || echo "  aplay failed"
    read -rp "  Heard it where (left-bottom, left-top, right-bottom, right-top, none)? " where
    echo "$a: $where" >> ~/speakers-amps-result.txt
done
for a in $AMPS; do A "$a DAC Switch" 1; done
rm -rf "$T"
systemctl --user start pipewire.socket pipewire-pulse.socket wireplumber pipewire pipewire-pulse
echo; cat ~/speakers-amps-result.txt
