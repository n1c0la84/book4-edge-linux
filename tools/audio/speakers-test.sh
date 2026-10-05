#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Four-speaker test through PipeWire (boot the "alt DT speakers.dtb" entry).
# PipeWire's UCM profile drives the speaker path; this only switches on the
# two new amplifiers (SpkrLeft2, SpkrRight2), which the profile does not know,
# then plays a quiet 1 kHz tone on each of the 4 speaker channels
# (FL, FR, RL, RR) in turn. Run as your user. Keep it quiet.
set -u
CARD=$(aplay -l 2>/dev/null | awk -F'[ :]' '/GalaxyBook4Edge/{print $2; exit}')
SINK=alsa_output.platform-sound.HiFi__Speaker__sink
[ -n "$CARD" ] || { echo "Sound card not found."; exit 1; }
amixer -D "hw:$CARD" scontrols | grep -qE "SpkrLeft2" || { echo "SpkrLeft2 controls missing: wrong DTB?"; exit 1; }

for a in SpkrLeft2 SpkrRight2; do
    amixer -q -D "hw:$CARD" cset "name=$a COMP Switch" 1
    amixer -q -D "hw:$CARD" cset "name=$a BOOST Switch" 1
    amixer -q -D "hw:$CARD" cset "name=$a DAC Switch" 1
    amixer -q -D "hw:$CARD" cset "name=$a VISENSE Switch" 0
    amixer -q -D "hw:$CARD" cset "name=$a WSA MODE" 0
    amixer -q -D "hw:$CARD" cset "name=$a PA Volume" 2
done
pactl set-default-sink "$SINK"
old=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.35
wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
: > ~/speakers-test-result.txt
names=(x FL FR RL RR)
for ch in 1 2 3 4; do
    read -rp "Channel $ch (${names[$ch]}): press Enter for 2 s of a quiet 1 kHz tone... " _
    PIPEWIRE_NODE=$SINK speaker-test -D pipewire -c 4 -s "$ch" -t sine -f 1000 -l 1 >/dev/null 2>&1
    read -rp "  Where did it come from (e.g. left-bottom, right-top, none)? " where
    echo "channel $ch (${names[$ch]}): $where" >> ~/speakers-test-result.txt
done
[ -n "${old:-}" ] && wpctl set-volume @DEFAULT_AUDIO_SINK@ "$old"
echo; cat ~/speakers-test-result.txt
echo; echo "Amplifier state now:"
for a in SpkrLeft SpkrRight SpkrLeft2 SpkrRight2; do
    printf '  %-11s DAC=%s PA=%s\n' $a \
        "$(amixer -D hw:$CARD cget "name=$a DAC Switch" | awk -F= '/: values/{print $2}')" \
        "$(amixer -D hw:$CARD cget "name=$a PA Volume" | awk -F= '/: values/{print $2}')"
done
