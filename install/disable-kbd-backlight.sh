#!/bin/bash
# Turn off and disable the experimental keyboard backlight driver (it blinks).
# The DKMS module stays installed but is no longer bound at boot.
#   bash install/disable-kbd-backlight.sh
set -eu
sudo -v
L=/sys/class/leds/samsung::kbd_backlight
[ -e $L ] && echo 0 | sudo tee $L/brightness >/dev/null
sudo systemctl disable --now book4-kbd-backlight.service
sudo modprobe -r book4_kbd_backlight 2>/dev/null || true
echo "keyboard backlight driver disabled (re-enable: sudo systemctl enable --now book4-kbd-backlight.service)"
