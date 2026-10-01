#!/bin/bash
# Load the keyboard backlight driver into the running kernel (RAM only) and test it.
#   bash test.sh          load + bind + set level 3
#   bash test.sh unload
set -u
cd "$(dirname "$0")"
OUT=$HOME/book4-kbd-test.txt
exec > >(tee "$OUT") 2>&1
sudo -v || exit 1
BUS=$(for d in /sys/bus/i2c/devices/i2c-*; do
        [ "$(basename "$(readlink -f "$d/..")")" = b94000.i2c ] && basename "$d"; done)
[ -n "$BUS" ] || { echo "b94000 bus not found (Anatase DTB?)"; exit 1; }
DEV=/sys/bus/i2c/devices/${BUS#i2c-}-0062

if [ "${1:-}" = unload ]; then
    [ -e "$DEV" ] && echo 0x62 | sudo tee /sys/bus/i2c/devices/$BUS/delete_device >/dev/null
    sudo rmmod book4_kbd_backlight
    exit
fi

make -s -C /lib/modules/$(uname -r)/build M="$PWD" modules 2>&1 | grep -vE 'differs|built by|You are using|built with|Skipping BTF'
lsmod | grep -q '^book4_kbd_backlight ' || sudo insmod ./book4_kbd_backlight.ko
[ -e "$DEV" ] || echo book4-kbd-backlight 0x62 | sudo tee /sys/bus/i2c/devices/$BUS/new_device >/dev/null
sleep 1
L=/sys/class/leds/samsung::kbd_backlight
ls -d $L && echo 3 | sudo tee $L/brightness >/dev/null
echo "brightness $(cat $L/brightness) / max $(cat $L/max_brightness), idle_timeout $(cat /sys/module/book4_kbd_backlight/parameters/idle_timeout) s"
upower -e | grep -i kbd || echo "upower: no keyboard backlight listed yet"
sudo dmesg | grep -i kbd | tail -3
echo "== done, output saved to $OUT"
