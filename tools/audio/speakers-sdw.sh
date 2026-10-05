#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# While all four speaker channels play (raw, no PipeWire), dump the SoundWire
# port registers of the four WSA883x amplifiers and the masters' debug info,
# to see whether the new amplifiers' data ports are enabled in the stream.
# Boot the "alt DT speakers.dtb" entry. Run as your user.
set -u
CARD=$(aplay -l 2>/dev/null | awk -F'[ :]' '/GalaxyBook4Edge/{print $2; exit}')
OUT=~/speakers-sdw.txt
sudo -v
T=$(mktemp -d)
python3 - "$T" <<'PYEOF'
import math, struct, sys, wave
with wave.open(f"{sys.argv[1]}/all.wav", "wb") as w:
    w.setnchannels(4); w.setsampwidth(2); w.setframerate(48000)
    f = bytearray()
    for i in range(48000 * 6):
        s = int(2000 * math.sin(2 * math.pi * 1000 * i / 48000))
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
    A "$m WSA_RX0 Digital Volume" 65; A "$m WSA_RX1 Digital Volume" 65
done
for a in SpkrLeft SpkrRight SpkrLeft2 SpkrRight2; do
    A "$a COMP Switch" 1; A "$a BOOST Switch" 1; A "$a DAC Switch" 1
    A "$a VISENSE Switch" 0; A "$a WSA MODE" 0; A "$a PA Volume" 1
done
aplay -q -D "hw:$CARD,1" "$T/all.wav" &
sleep 2
{
echo "== soundwire debugfs"
sudo sh -c 'ls -R /sys/kernel/debug/soundwire 2>/dev/null | head -40'
for s in sdw:1:0:0217:0202:00:1 sdw:1:0:0217:0202:00:2 sdw:4:0:0217:0202:00:1 sdw:4:0:0217:0202:00:2; do
    f=$(sudo sh -c "ls -d /sys/kernel/debug/soundwire/*/$s 2>/dev/null" | head -1)
    echo "== $s ($f)"
    [ -n "$f" ] && sudo cat "$f/registers" 2>/dev/null | head -120
done
for m in master-1-0 master-4-0; do
    echo "== $m qualcomm-registers"
    sudo cat /sys/kernel/debug/soundwire/$m/qualcomm-sdw/qualcomm-registers 2>/dev/null
done
echo "== dmesg during playback"
sudo dmesg | tail -15
} > "$OUT" 2>&1
wait
rm -rf "$T"
systemctl --user start pipewire.socket pipewire-pulse.socket wireplumber pipewire pipewire-pulse
echo "saved $OUT (did you hear more than two speakers during the 6 s?)"
