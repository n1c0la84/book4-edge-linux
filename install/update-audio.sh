#!/bin/bash
# Install the UCM profile from this repo and restart the user audio services.
#   bash install/update-audio.sh
set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)
sudo -v
sudo install -m 644 "$REPO"/userspace/audio/ucm2/*.conf /usr/share/alsa/ucm2/Qualcomm/x1e80100/
systemctl --user restart wireplumber pipewire pipewire-pulse
sleep 3
wpctl status | sed -n '/Sinks:/,/Filters:/p'
