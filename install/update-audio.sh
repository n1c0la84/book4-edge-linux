#!/bin/bash
# Install the UCM profile and the PipeWire speaker crossover from this repo,
# and restart the user audio services.
#   bash install/update-audio.sh
set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)
sudo -v
# Limiter used by the speaker filter (Fedora; on Arch: pacman -S swh-plugins)
rpm -q ladspa-swh-plugins >/dev/null 2>&1 || sudo dnf install -y ladspa-swh-plugins
sudo install -m 644 "$REPO"/userspace/audio/ucm2/*.conf /usr/share/alsa/ucm2/Qualcomm/x1e80100/
# Stereo "Speakers" sink with a crossover (tweeters get highs only), and no
# up-mixing on the raw four-channel sink. Per user.
install -D -m 644 "$REPO"/userspace/audio/pipewire/book4-speakers.conf \
    ~/.config/pipewire/pipewire.conf.d/book4-speakers.conf
install -D -m 644 "$REPO"/userspace/audio/pipewire/book4-speakers-wireplumber.conf \
    ~/.config/wireplumber/wireplumber.conf.d/book4-speakers.conf
systemctl --user restart wireplumber pipewire pipewire-pulse
sleep 3
# The raw sink's volume is the amplifiers' gain; the Speakers sink's volume is
# the one to use day to day.
RAW=alsa_output.platform-sound.HiFi__Speaker__sink
id=$(pw-dump | python3 -c "import json,sys; print(next((o['id'] for o in json.load(sys.stdin) if ((o.get('info') or {}).get('props') or {}).get('node.name')=='$RAW'),''))")
[ -n "$id" ] && wpctl set-volume "$id" 1.0 && wpctl set-mute "$id" 0
wpctl status | sed -n '/Sinks:/,/Sources:/p' | head -12
