#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Fingerprint reader (EgisTec 1c7a:05a1, libfprint egismoc) on Fedora:
#  1. udev rule: no USB autosuspend for the sensor (it dropped off the bus);
#  2. default DTB = the four-speaker DTB plus usb_2 enabled
#     (dts/patches/0004); the previous default stays as the "alt DT" entry;
#  3. fingerprint for login, the KDE lock screen and sudo
#     (authselect feature with-fingerprint; the password always works too).
# Needs the SDCP libfprint first: install/fingerprint-libfprint.sh.
# Then enroll: fprintd-enroll   (and fprintd-verify to check)
#
#   bash install/fingerprint.sh          # all of the above
#   bash install/fingerprint.sh undo     # back to the previous DTB, PAM off
# Run as your user on Fedora.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
HOOK=/etc/kernel/install.d/99-book4-devicetree.install
SRC=${FP_DTB:-$HOME/src/speakers/fingerprint.dtb}
K=$(cat /etc/book4/default-kernel)
sudo -v
if [ "${1:-}" = undo ]; then
    [ -e /etc/book4/default-dtb.prev-fp ] && sudo cp -p /etc/book4/default-dtb.prev-fp /etc/book4/default-dtb
    sudo authselect disable-feature with-fingerprint
    sudo "$HOOK" add "$K"
    echo "== default DTB: $(cat /etc/book4/default-dtb)"
    exit 0
fi
# Without SDCP the sensor forgets every print (see install/fingerprint-libfprint.sh)
rpm -q libfprint | grep -q sdcp ||
    { echo "libfprint is not the SDCP build: run install/fingerprint-libfprint.sh first." >&2; exit 1; }
echo "== 1. udev rule"
sudo install -m 644 "$REPO"/userspace/fingerprint/90-book4-fingerprint.rules /etc/udev/rules.d/
sudo udevadm control --reload
sudo udevadm trigger --action=add --attr-match=idVendor=1c7a --subsystem-match=usb || true

echo "== 2. default DTB"
[ -e "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }
DTS=$(dtc -q -I dtb -O dts "$SRC")   # captured: grep -q in a pipe trips pipefail
grep -q 'TweeterLeft' <<<"$DTS" || { echo "$SRC: no tweeters?" >&2; exit 1; }
awk '/usb@a200000 \{/{f=1} f&&/status = "okay"/{ok=1} f&&/^\t\t\};/{exit} END{exit !ok}' <<<"$DTS" ||
    { echo "$SRC: usb_2 not enabled?" >&2; exit 1; }
sudo dtc -q -I dtb -O dtb -p 8192 -o /boot/dtb-test/fingerprint-default.dtb "$SRC"
grep -q fingerprint-default /etc/book4/default-dtb || sudo cp -p /etc/book4/default-dtb /etc/book4/default-dtb.prev-fp
prev=$(awk '{print $2}' /etc/book4/default-dtb.prev-fp)
echo "$K /dtb-test/fingerprint-default.dtb" | sudo tee /etc/book4/default-dtb >/dev/null
echo "$prev" | sudo tee /etc/book4/test-dtb >/dev/null
sudo "$HOOK" add "$K"
echo "   default: $(cat /etc/book4/default-dtb); alt entry: $(cat /etc/book4/test-dtb)"

echo "== 3. PAM: fingerprint for login, lock screen, sudo"
sudo authselect enable-feature with-fingerprint
authselect current
echo
fprintd-list "$USER" | tail -n +2
echo "Done. Reboot into the normal entry; fingers: fprintd-enroll / fprintd-delete $USER"
