#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# The front camera (OV02C10 behind CAMSS) for apps that only speak V4L2, such
# as Qt Multimedia apps (Monologue). The camera works only through libcamera
# (PipeWire offers it as "Built-in Front Camera" to browsers and portal apps);
# Qt 6.12 lists V4L2 devices only, and libcamera's V4L2 compatibility layer
# (libcamerify) advertises no frame rates for this sensor, so Qt drops it.
# Same approach as Omarchy's Cam Link setup: v4l2-relayd feeds a v4l2loopback
# device ("Book4 Camera", 1280x720 NV12 30 fps) from libcamerasrc, and opens
# the real camera only while an app reads the virtual one. Run as your user:
#
#   bash install/arch/camera-relay.sh          install and start
#   bash install/arch/camera-relay.sh undo     stop and remove (packages stay)
set -euo pipefail
LABEL="Book4 Camera"
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
sudo -v

if [ "${1:-}" = undo ]; then
    sudo systemctl stop v4l2-relayd@book4.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/multi-user.target.wants/v4l2-relayd@book4.service
    sudo rm -rf /etc/systemd/system/v4l2-relayd@book4.service.d /etc/systemd/system/book4-camera-loopback.service \
        /etc/v4l2-relayd.d/book4.conf
    sudo systemctl daemon-reload
    echo "removed (packages and /etc/modprobe.d/v4l2loopback-exclusive-caps.conf stay)"; exit 0
fi

echo "== 1. packages (v4l2loopback is built by DKMS for linux-book4)"
sudo pacman -S --needed --noconfirm dkms v4l2loopback-dkms v4l2loopback-utils v4l2-relayd gst-plugin-libcamera
modinfo -k "$(uname -r)" v4l2loopback >/dev/null 2>&1 ||
    sudo dkms autoinstall -k "$(uname -r)"
modinfo -k "$(uname -r)" v4l2loopback >/dev/null || { echo "error: v4l2loopback not built for $(uname -r)" >&2; exit 1; }

echo "== 2. configuration"
# Without it the module's own default device shows up as "Dummy video device".
echo "options v4l2loopback exclusive_caps=1" | sudo tee /etc/modprobe.d/v4l2loopback-exclusive-caps.conf >/dev/null
sudo install -d /etc/v4l2-relayd.d /etc/systemd/system/v4l2-relayd@book4.service.d
sudo tee /etc/v4l2-relayd.d/book4.conf >/dev/null <<EOF
# Galaxy Book4 Edge front camera (book4-edge-linux install/arch/camera-relay.sh)
VIDEOSRC="libcamerasrc"
FORMAT=NV12
WIDTH=1280
HEIGHT=720
FRAMERATE=30/1
CARD_LABEL="$LABEL"
EOF
sudo tee /etc/systemd/system/book4-camera-loopback.service >/dev/null <<EOF
# book4-edge-linux install/arch/camera-relay.sh (after Omarchy's camlink-4k-loopback.service)
[Unit]
Description=Create the Book4 virtual camera
After=systemd-modules-load.service

[Service]
Type=oneshot
ExecStart=/usr/bin/modprobe v4l2loopback
ExecStart=/bin/sh -c 'grep -qsx "$LABEL" /sys/devices/virtual/video4linux/*/name || exec v4l2loopback-ctl add -n "$LABEL" -x 1'
EOF
sudo tee /etc/systemd/system/v4l2-relayd@book4.service.d/book4.conf >/dev/null <<'EOF'
# book4-edge-linux install/arch/camera-relay.sh (after Omarchy's v4l2-relayd@camlink drop-in)
[Unit]
Requires=book4-camera-loopback.service
After=book4-camera-loopback.service

[Service]
RestartSec=2
# sync=false: a synced sink drops frames stamped with their capture time.
ExecStart=
ExecStart=/bin/sh -c 'DEVICE=$(grep -l -m1 -E "^${CARD_LABEL}$" /sys/devices/virtual/video4linux/*/name | cut -d/ -f6); exec /usr/bin/v4l2-relayd -i "${VIDEOSRC}" $${SPLASHSRC:+-s "$${SPLASHSRC}"} -o "appsrc name=appsrc caps=video/x-raw,format=${FORMAT},width=${WIDTH},height=${HEIGHT},framerate=${FRAMERATE} ! videoconvert ! v4l2sink name=v4l2sink sync=false device=/dev/$${DEVICE}" $EXTRA_OPTS'
EOF
sudo systemctl daemon-reload

echo "== 3. start"
# Drop-ins cannot carry [Install]; wire the instance to boot explicitly.
sudo systemctl add-wants multi-user.target v4l2-relayd@book4.service
sudo systemctl start v4l2-relayd@book4.service
sleep 2
systemctl --no-pager -n 5 status v4l2-relayd@book4.service | sed 's/^/   /' | tail -8
dev=$(grep -l -x "$LABEL" /sys/devices/virtual/video4linux/*/name 2>/dev/null | head -1 | cut -d/ -f6)
[ -n "$dev" ] && echo "   virtual camera: /dev/$dev \"$LABEL\"" || echo "   (no virtual camera yet; see the status above)"
rm -f "$HOME/.local/share/applications/monologue.desktop"   # the libcamerify launcher is not needed any more
echo; echo "Open Monologue (or any V4L2 app) and pick \"$LABEL\"."
