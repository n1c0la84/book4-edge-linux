#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Raw four-speaker test: no PipeWire, no channel maps. Writes a 4-channel
# 48 kHz file with a quiet 1 kHz tone in ONE raw PCM channel at a time and
# plays it straight to the speaker device (hw:CARD,1). The DSP's 4-channel
# order is FL, LB, FR, RB (sound/soc/qcom/x1e80100.c).
# Boot the "alt DT speakers.dtb" entry first. Run as your user.
set -u
CARD=$(aplay -l 2>/dev/null | awk -F'[ :]' '/GalaxyBook4Edge/{print $2; exit}')
[ -n "$CARD" ] || { echo "Sound card not found."; exit 1; }
T=$(mktemp -d)
python3 - "$T" <<'PYEOF'
import math, struct, sys, wave
for ch in range(4):
    with wave.open(f"{sys.argv[1]}/ch{ch+1}.wav", "wb") as w:
        w.setnchannels(4); w.setsampwidth(2); w.setframerate(48000)
        frames = bytearray()
        for i in range(48000 * 2):
            s = int(3000 * math.sin(2 * math.pi * 1000 * i / 48000))  # about -21 dBFS
            frame = [0, 0, 0, 0]; frame[ch] = s
            frames += struct.pack("<4h", *frame)
        w.writeframes(bytes(frames))
PYEOF

echo "== pausing PipeWire (before touching the mixer)"
systemctl --user stop pipewire.socket pipewire-pulse.socket pipewire wireplumber pipewire-pulse 2>/dev/null
sleep 1
A() { amixer -q -D "hw:$CARD" cset "name=$1" "$2"; }
# what the UCM verb + Speaker device do, plus the two new amplifiers
A "WSA_CODEC_DMA_RX_0 Audio Mixer MultiMedia2" 1
for m in WSA WSA2; do
    A "$m WSA RX0 MUX" AIF1_PB; A "$m WSA RX1 MUX" AIF1_PB
    A "$m WSA_RX0 INP0" RX0;    A "$m WSA_RX1 INP0" RX1
    A "$m WSA_RX0 Digital Volume" 70; A "$m WSA_RX1 Digital Volume" 70
done
for a in SpkrLeft SpkrRight SpkrLeft2 SpkrRight2; do
    A "$a COMP Switch" 1; A "$a BOOST Switch" 1; A "$a DAC Switch" 1
    A "$a VISENSE Switch" 0; A "$a WSA MODE" 0; A "$a PA Volume" 2
done

: > ~/speakers-raw-result.txt
names=(x "FL (expect SpkrLeft)" "LB (expect SpkrLeft2?)" "FR (expect SpkrRight2?)" "RB (expect SpkrRight)")
for ch in 1 2 3 4; do
    read -rp "Raw channel $ch ${names[$ch]}: press Enter for 2 s of tone... " _
    aplay -q -D "hw:$CARD,1" "$T/ch$ch.wav" || echo "  aplay failed"
    read -rp "  Where did it come from (left-bottom, left-top, right-..., none)? " where
    echo "raw channel $ch: $where" >> ~/speakers-raw-result.txt
done
rm -rf "$T"
echo "== restarting PipeWire"
systemctl --user start pipewire.socket pipewire-pulse.socket wireplumber pipewire pipewire-pulse
echo; cat ~/speakers-raw-result.txt
