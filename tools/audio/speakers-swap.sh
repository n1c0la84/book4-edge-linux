#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Does each WSA macro receive a second channel? Feed the macros' FIRST
# output (RX0, the amplifiers that work) from their SECOND input (RX1), then
# play each raw PCM channel in turn. Raw, no PipeWire. Run as your user.
set -u
CARD=$(aplay -l 2>/dev/null | awk -F'[ :]' '/GalaxyBook4Edge/{print $2; exit}')
T=$(mktemp -d)
python3 - "$T" <<'PYEOF'
import math, struct, sys, wave
for ch in range(4):
    with wave.open(f"{sys.argv[1]}/ch{ch+1}.wav", "wb") as w:
        w.setnchannels(4); w.setsampwidth(2); w.setframerate(48000)
        f = bytearray()
        for i in range(48000 * 2):
            fr = [0, 0, 0, 0]; fr[ch] = int(4000 * math.sin(2 * math.pi * 1000 * i / 48000))
            f += struct.pack("<4h", *fr)
        w.writeframes(bytes(f))
PYEOF
systemctl --user stop pipewire.socket pipewire-pulse.socket pipewire wireplumber pipewire-pulse 2>/dev/null
sleep 1
A() { amixer -q -D "hw:$CARD" cset "name=$1" "$2"; }
A "WSA_CODEC_DMA_RX_0 Audio Mixer MultiMedia2" 1
for m in WSA WSA2; do
    A "$m WSA RX0 MUX" AIF1_PB; A "$m WSA RX1 MUX" AIF1_PB
    A "$m WSA_RX0 INP0" RX1          # <-- first output now takes the SECOND channel
    A "$m WSA_RX1 INP0" RX1
    A "$m WSA_RX0 Digital Volume" 72; A "$m WSA_RX1 Digital Volume" 72
done
for a in SpkrLeft SpkrRight SpkrLeft2 SpkrRight2; do
    A "$a COMP Switch" 1; A "$a BOOST Switch" 1; A "$a DAC Switch" 1
    A "$a VISENSE Switch" 0; A "$a WSA MODE" 0; A "$a PA Volume" 3
done
: > ~/speakers-swap-result.txt
for ch in 1 2 3 4; do
    read -rp "Raw channel $ch: press Enter for 2 s of tone... " _
    aplay -q -D "hw:$CARD,1" "$T/ch$ch.wav" || echo "  aplay failed"
    read -rp "  Heard it where (right-front, left-bottom, other, none)? " where
    echo "swap, raw channel $ch: $where" >> ~/speakers-swap-result.txt
done
for m in WSA WSA2; do A "$m WSA_RX0 INP0" RX0; done   # back to normal
rm -rf "$T"
systemctl --user start pipewire.socket pipewire-pulse.socket wireplumber pipewire pipewire-pulse
echo; cat ~/speakers-swap-result.txt
