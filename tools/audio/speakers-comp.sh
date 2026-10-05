#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Own-port four-speaker DTB (speakers.dtb): woofers (SpkrLeft/SpkrRight) fully
# on, tweeters (SpkrLeft2/SpkrRight2) with COMP/BOOST varied, to find which
# of their side ports collides on the bus. Raw, no PipeWire. Run as your user.
set -u
CARD=$(aplay -l 2>/dev/null | awk -F'[ :]' '/GalaxyBook4Edge/{print $2; exit}')
T=$(mktemp -d)
python3 - "$T" <<'PYEOF'
import math, struct, sys, wave
with wave.open(f"{sys.argv[1]}/all.wav", "wb") as w:
    w.setnchannels(4); w.setsampwidth(2); w.setframerate(48000)
    f = bytearray()
    for i in range(48000 * 3):
        s = int(4000 * math.sin(2 * math.pi * 3000 * i / 48000))   # 3 kHz: tweeter range
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
for a in SpkrLeft SpkrRight SpkrLeft2 SpkrRight2; do
    A "$a VISENSE Switch" 0; A "$a WSA MODE" 0; A "$a PA Volume" 3
done
for a in SpkrLeft SpkrRight; do A "$a COMP Switch" 1; A "$a BOOST Switch" 1; done
: > ~/speakers-comp-result.txt
for v in "0 0" "1 0" "0 1" "1 1"; do
    set -- $v
    for a in SpkrLeft2 SpkrRight2; do A "$a COMP Switch" $1; A "$a BOOST Switch" $2; done
    for a in SpkrLeft SpkrRight; do A "$a DAC Switch" 0; done
    for a in SpkrLeft2 SpkrRight2; do A "$a DAC Switch" 1; done
    read -rp "Tweeters only, COMP=$1 BOOST=$2: Enter for 3 s of a 3 kHz tone... " _
    aplay -q -D "hw:$CARD,1" "$T/all.wav" || echo "  aplay failed"
    read -rp "  Clear tone, tone+noise, or only noise? Which sides? " d
    for a in SpkrLeft SpkrRight; do A "$a DAC Switch" 1; done
    read -rp "  Now all four, same settings: Enter... " _
    aplay -q -D "hw:$CARD,1" "$T/all.wav" || echo "  aplay failed"
    read -rp "  Louder/fuller than tweeters alone? " e
    echo "tweeters COMP=$1 BOOST=$2: alone: $d | all four: $e" >> ~/speakers-comp-result.txt
done
rm -rf "$T"
systemctl --user start pipewire.socket pipewire-pulse.socket wireplumber pipewire pipewire-pulse
echo; cat ~/speakers-comp-result.txt
