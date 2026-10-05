#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Give the Arch subvolume Fedora's audio setup for the four speakers: the UCM
# profile (tweeters, digital gain), the PipeWire crossover + limiter and the
# WirePlumber rule (for the Arch user), and swh-plugins for the limiter.
# Run as your user on Fedora, with Arch not running; again after changing
# anything under userspace/audio.
#
#   bash install/arch/sync-audio.sh
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
TOP=/mnt/btrfs-top
R=$TOP/arch
DEV=/dev/sda5
AUSER=${ARCH_USER:-$USER}
ns() { sudo systemd-nspawn -q -D "$R" --resolv-conf=replace-uplink "$@"; }

[ -e /etc/fedora-release ] || { echo "Run this on Fedora." >&2; exit 1; }
sudo -v
echo "== 1. Arch subvolume"
sudo mkdir -p $TOP
mounted_here=0
if ! mountpoint -q $TOP; then
    sudo mount -o subvolid=5 $DEV $TOP
    mounted_here=1
fi
cleanup() { [ $mounted_here = 1 ] && sudo umount $TOP || true; }
trap cleanup EXIT
[ -e "$R/etc/mkinitcpio.conf.d/book4.conf" ] || { echo "$R does not look like our Arch install." >&2; exit 1; }
H=$R/home/$AUSER
[ -d "$H" ] || { echo "No $H in Arch (set ARCH_USER)." >&2; exit 1; }
own=$(sudo stat -c %u:%g "$H")

echo "== 2. swh-plugins (look-ahead limiter)"
ns pacman -Q swh-plugins >/dev/null 2>&1 || ns pacman -S --noconfirm --needed swh-plugins
ns sh -c 'ls /usr/lib/ladspa/fast_lookahead_limiter_1913.so'

echo "== 3. UCM profile"
sudo install -m 644 "$REPO"/userspace/audio/ucm2/*.conf "$R/usr/share/alsa/ucm2/Qualcomm/x1e80100/"
sudo ls -l "$R"/usr/share/alsa/ucm2/conf.d/x1e80100/

echo "== 4. PipeWire crossover and WirePlumber rule for $AUSER"
for d in .config .config/pipewire .config/pipewire/pipewire.conf.d .config/wireplumber .config/wireplumber/wireplumber.conf.d; do
    sudo install -d -o "${own%:*}" -g "${own#*:}" "$H/$d"
done
sudo install -m 644 -o "${own%:*}" -g "${own#*:}" "$REPO"/userspace/audio/pipewire/book4-speakers.conf \
    "$H/.config/pipewire/pipewire.conf.d/book4-speakers.conf"
sudo install -m 644 -o "${own%:*}" -g "${own#*:}" "$REPO"/userspace/audio/pipewire/book4-speakers-wireplumber.conf \
    "$H/.config/wireplumber/wireplumber.conf.d/book4-speakers.conf"
echo "Done. In Arch: the Speaker output now uses all four speakers; check with"
echo "  speaker-test -D pipewire -c 2 -t wav -l 1"
