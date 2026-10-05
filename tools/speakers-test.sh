#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Four-speaker test (boot the "alt DT speakers.dtb" entry first).
# 1) checks that all four WSA883x amplifiers have a driver,
# 2) enables the two new ones (SpkrLeft2, SpkrRight2) with low gain,
# 3) plays a quiet 1 kHz tone on each of the 4 channels in turn, so you can
#    tell which speaker each channel drives (hand on the grilles helps).
# PipeWire is paused during the tone and restarted afterwards.
# Run as your user. Keep the volume low; nothing bass-heavy.
set -u
CARD=$(aplay -l 2>/dev/null | awk -F'[ :]' '/GalaxyBook4Edge/{print $2; exit}')
[ -n "$CARD" ] || { echo "Sound card not found."; exit 1; }
echo "== amplifiers on the speaker buses"
for d in /sys/bus/soundwire/devices/sdw:[14]:0:0217:0202:00:*; do
    printf '  %s  driver=%s  status=%s\n' "${d##*/}" \
        "$(basename "$(readlink "$d/driver" 2>/dev/null)" 2>/dev/null)" "$(cat "$d/status" 2>/dev/null)"
done
echo "== mixer controls for the new amplifiers"
amixer -D "hw:$CARD" scontrols | grep -E "Spkr(Left|Right)2" || { echo "  none: SpkrLeft2/SpkrRight2 not registered (check dmesg | grep -i wsa)"; exit 1; }

set_amp() {  # $1 prefix
    amixer -q -D "hw:$CARD" cset "name=$1 COMP Switch" 1
    amixer -q -D "hw:$CARD" cset "name=$1 BOOST Switch" 1
    amixer -q -D "hw:$CARD" cset "name=$1 DAC Switch" 1
    amixer -q -D "hw:$CARD" cset "name=$1 VISENSE Switch" 0
    amixer -q -D "hw:$CARD" cset "name=$1 WSA MODE" 0
}
for a in SpkrLeft SpkrRight SpkrLeft2 SpkrRight2; do set_amp $a; done
# Low PA gain on all four for the test (restored by the profile later)
for a in SpkrLeft SpkrRight SpkrLeft2 SpkrRight2; do
    amixer -q -D "hw:$CARD" cset "name=$a PA Volume" 2 2>/dev/null || true
done
# Route both inputs of both WSA macros (as the UCM verb does)
for m in WSA WSA2; do
    amixer -q -D "hw:$CARD" cset "name=$m WSA RX0 MUX" AIF1_PB
    amixer -q -D "hw:$CARD" cset "name=$m WSA RX1 MUX" AIF1_PB
    amixer -q -D "hw:$CARD" cset "name=$m WSA_RX0 INP0" RX0
    amixer -q -D "hw:$CARD" cset "name=$m WSA_RX1 INP0" RX1
    amixer -q -D "hw:$CARD" cset "name=$m WSA_RX0 Digital Volume" 70
    amixer -q -D "hw:$CARD" cset "name=$m WSA_RX1 Digital Volume" 70
done
amixer -q -D "hw:$CARD" cset "name=WSA_CODEC_DMA_RX_0 Audio Mixer MultiMedia2" 1

echo "== pausing PipeWire"
systemctl --user stop pipewire.socket pipewire-pulse.socket pipewire wireplumber pipewire-pulse 2>/dev/null
sleep 1
for ch in 1 2 3 4; do
    read -rp "Channel $ch: press Enter to play 2 s of a quiet 1 kHz tone... " _
    speaker-test -q -D "plughw:$CARD,1" -c 4 -s "$ch" -t sine -f 1000 -l 1 >/dev/null 2>&1
    read -rp "  Which speaker did you hear (e.g. left-bottom, right-top, none)? " where
    echo "channel $ch: $where" >> ~/speakers-test-result.txt
done
echo "== restarting PipeWire"
systemctl --user start pipewire.socket pipewire-pulse.socket wireplumber pipewire pipewire-pulse
echo; cat ~/speakers-test-result.txt
