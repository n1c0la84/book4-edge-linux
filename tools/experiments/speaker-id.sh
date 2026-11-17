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
#   bash tools/experiments/speaker-id.sh ab [200]   per side, A/B at one frequency (the real test)
#
# Channels as the device tree maps them (docs/audio.md): 1 FL, 2 FR, 3 RL, 4 RR.
set -euo pipefail
sink=alsa_output.platform-sound.HiFi__Speaker__sink
pactl list short sinks | grep -q "$sink" || { echo "error: $sink not found" >&2; exit 1; }
dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT

tone() {  # $1 channel 1-4, $2 Hz -> WAV path
    python3 -I - "$1" "$2" "$dir/c$1-$2.wav" <<'EOF'
import sys, math, struct, wave
ch, f, out = int(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
rate, secs, amp = 48000, 1.5, 0.063   # -24 dBFS
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
