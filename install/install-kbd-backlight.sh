#!/bin/bash
# Install the keyboard backlight driver (DKMS) and its bind service.
#   bash install/install-kbd-backlight.sh
set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)
K=$(uname -r)
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$REPO/drivers/book4-kbd-backlight/dkms.conf")
SRC=/usr/src/book4-kbd-backlight-$VER
sudo -v
# A test copy may be loaded: unbind it first.
[ -x "$REPO/drivers/book4-kbd-backlight/test.sh" ] && bash "$REPO/drivers/book4-kbd-backlight/test.sh" unload 2>/dev/null || true
sudo rm -rf "$SRC"; sudo install -d "$SRC"
sudo install -m 644 "$REPO"/drivers/book4-kbd-backlight/{book4_kbd_backlight.c,Kbuild,dkms.conf} "$SRC/"
for old in $(dkms status book4-kbd-backlight 2>/dev/null | sed -n 's#^book4-kbd-backlight/\([^,]*\),.*#\1#p' | sort -u); do
    sudo dkms remove "book4-kbd-backlight/$old" --all || true
    sudo rm -rf "/usr/src/book4-kbd-backlight-$old"
done
sudo dkms add "book4-kbd-backlight/$VER"
sudo dkms install "book4-kbd-backlight/$VER" -k "$K"
sudo install -m 755 "$REPO/userspace/kbd-backlight/book4-kbd-backlight-bind" /usr/local/sbin/book4-kbd-backlight-bind
sudo install -m 644 "$REPO/userspace/kbd-backlight/book4-kbd-backlight.service" /etc/systemd/system/book4-kbd-backlight.service
sudo systemctl daemon-reload
sudo systemctl stop book4-kbd-backlight.service 2>/dev/null || true
sudo modprobe -r book4_kbd_backlight 2>/dev/null || true
sudo systemctl enable --now book4-kbd-backlight.service
sleep 1
L=/sys/class/leds/samsung::kbd_backlight
echo "backlight: $(cat $L/brightness)/$(cat $L/max_brightness), module $(modinfo -n book4_kbd_backlight)"
sudo systemctl restart upower.service   # it only looks for keyboard backlights at start
echo "GNOME slider: in quick settings (log out/in if it does not update)."
