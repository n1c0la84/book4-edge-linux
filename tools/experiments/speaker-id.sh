#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Which amplifier drives which speaker (omarchy#15860, 17 November): play a
# short quiet tone to ONE channel of the raw 4-channel speaker sink at a
# time, bypassing the crossover, at 300 Hz and at 4 kHz. Listen at each end
# of the base: a woofer is clearly audible at 300 Hz, a tweeter almost
# silent at 300 Hz and loud at 4 kHz. Levels are kept low (-24 dBFS, 1.5 s)
# because the tweeters get no high-pass here.
#
#   bash tools/experiments/speaker-id.sh            all four channels, both tones
#   bash tools/experiments/speaker-id.sh 3 300      one channel (1-4), one frequency
#   bash tools/experiments/speaker-id.sh ab [200]   per side, A/B at one frequency
#   bash tools/experiments/speaker-id.sh phone      5 s tones for a phone spectrum app at each slit
#   bash tools/experiments/speaker-id.sh amp        one amplifier at a time (DAC Switch), phone at each slit
#
# Channels as the device tree maps them (docs/audio.md): 1 FL, 2 FR, 3 RL, 4 RR.
set -euo pipefail
sink=alsa_output.platform-sound.HiFi__Speaker__sink
pactl list short sinks | grep -q "$sink" || { echo "error: $sink not found" >&2; exit 1; }
dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT

SECS=${SECS:-1.5}
tone() {  # $1 channel 1-4, $2 Hz -> WAV path
    SECS=$SECS python3 -I - "$1" "$2" "$dir/c$1-$2.wav" <<'EOF'
import sys, math, struct, wave, os
ch, f, out = int(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
rate, secs, amp = 48000, float(os.environ.get('SECS', '1.5')), 0.063   # -24 dBFS
n = int(rate * secs); fade = int(rate * 0.02)
w = wave.open(out, 'wb'); w.setnchannels(4); w.setsampwidth(2); w.setframerate(rate)
frames = bytearray()
for i in range(n):
    g = min(1.0, i / fade, (n - 1 - i) / fade)
    v = int(32767 * amp * g * math.sin(2 * math.pi * f * i / rate))
    s = [0, 0, 0, 0]; s[ch - 1] = v
    frames += struct.pack('<4h', *s)
w.writeframes(bytes(frames)); w.close()
EOF
    echo "$dir/c$1-$2.wav"
}
play() {  # $1 channel, $2 Hz
    local names=(FL FR RL RR)
    printf 'channel %s (%s), %5s Hz ... ' "$1" "${names[$1-1]}" "$2"
    pw-play --target "$sink" "$(tone "$1" "$2")"
    echo done
    sleep 0.7
}

if [ "${1:-}" = amp ]; then
    # One amplifier at a time, by its own DAC Switch (no routing involved):
    # the other three are switched off with the sink suspended (the switch is
    # only read when a stream starts), then a 1 kHz tone plays on all four
    # channels; read the phone at the left slit, then at the right slit.
    amps=$(amixer -c 0 controls | sed -n "s/.*name='\(\(Spkr\|Tweeter\)[A-Za-z]*\) DAC Switch'.*/\1/p")
    [ -n "$amps" ] || { echo "error: no amplifier DAC Switch controls found" >&2; exit 1; }
    declare -A orig
    for a in $amps; do orig[$a]=$(amixer -D hw:0 cget name="$a DAC Switch" | sed -n 's/^  : values=//p'); done
    setall() { pactl suspend-sink "$sink" 1; sleep 1
               for a in $amps; do amixer -q -D hw:0 cset name="$a DAC Switch" "$([ "$a" = "$1" ] && echo on || echo off)"; done
               sleep 0.2; pactl suspend-sink "$sink" 0; sleep 0.5; }
    restore() { pactl suspend-sink "$sink" 1; sleep 1
                for a in $amps; do amixer -q -D hw:0 cset name="$a DAC Switch" "${orig[$a]}"; done
                pactl suspend-sink "$sink" 0; }
    trap 'restore; rm -rf "$dir"' EXIT
    SECS=5
    all4() {  # 1 kHz on all four channels
        python3 -I - "$dir/all.wav" <<'PY'
import sys, math, struct, wave
rate, secs, amp, f = 48000, 5.0, 0.063, 1000.0
n = int(rate * secs); fade = int(rate * 0.02)
w = wave.open(sys.argv[1], 'wb'); w.setnchannels(4); w.setsampwidth(2); w.setframerate(rate)
b = bytearray()
for i in range(n):
    g = min(1.0, i / fade, (n - 1 - i) / fade)
    v = int(32767 * amp * g * math.sin(2 * math.pi * f * i / rate))
    b += struct.pack('<4h', v, v, v, v)
w.writeframes(bytes(b)); w.close()
PY
    }
    all4
    for a in $amps; do
        setall "$a"
        for spot in left right; do
            read -r -p "Only '$a' on. Phone at the $spot slit, Enter to play 1 kHz for 5 s. " _
            pw-play --target "$sink" "$dir/all.wav"
            read -r -p "  peak at 1 kHz ($a, $spot slit) = ? dB " _
        done
    done
    echo "All amplifiers back as they were."
    exit 0
fi
if [ "${1:-}" = phone ]; then
    # A phone spectrum app (e.g. Spectroid) about 2 cm from each slit: each
    # tone lasts 5 s; read the peak height at the tone frequency.
    SECS=5
    for f in 1000 300; do
        for spot in "left 1 3" "right 2 4"; do
            set -- $spot
            read -r -p "Phone at the $1 slit, $f Hz. Enter to play channel $2, then channel $3. " _
            play $2 $f; play $3 $f
            read -r -p "  peak at $f Hz: channel $2 = ? dB, channel $3 = ? dB (type them, Enter) " _
        done
    done
    echo "Then the cross check, phone at the LEFT slit, 1000 Hz: channels 2 and 4."
    read -r -p "Enter to play channel 2, then 4. " _; play 2 1000; play 4 1000
    read -r -p "  peak: channel 2 = ? dB, channel 4 = ? dB " _
    exit 0
fi
if [ "${1:-}" = ab ]; then
    # Same frequency, the two channels of one side back to back: the human ear
    # is much more sensitive at 4 kHz than at 300 Hz, so compare at one
    # frequency. At 200 Hz a woofer is clearly louder than a tweeter.
    f=${2:-200}
    for pair in "1 3 left" "2 4 right"; do
        set -- $pair
        echo "$3 side, $f Hz: A = channel $1, then B = channel $2 (twice)"
        for r in 1 2; do play $1 $f; play $2 $f; done
        read -r -p "  which was louder at $f Hz, A (channel $1) or B (channel $2)? " _
    done
    exit 0
fi
if [ $# -ge 2 ]; then play "$1" "$2"; exit 0; fi
echo "Listen at the left and right ends of the base. Each line plays one channel."
for c in 1 2 3 4; do
    play $c 300
    play $c 4000
    read -r -p "  channel $c: which side, and louder at 300 Hz or at 4 kHz? (Enter to go on) " _
done
