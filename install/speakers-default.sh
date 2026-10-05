#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Make the four-speaker device tree (camera + privacy LED + tweeters) the
# default DTB for the default kernel (Fedora and the Arch entry). The previous
# camera DTB stays bootable as the "alt DT camera.dtb" entry.
#   bash install/speakers-default.sh        # install
#   bash install/speakers-default.sh undo   # back to the camera DTB
# Run as your user. DTB: the camera DTS built on dts/patches tweeter patch.
set -euo pipefail
HOOK=/etc/kernel/install.d/99-book4-devicetree.install
SRC=${SPEAKERS_DTB:-$HOME/src/speakers/four-speakers.dtb}
K=$(cat /etc/book4/default-kernel)
sudo -v
if [ "${1:-}" = undo ]; then
    [ -e /etc/book4/default-dtb.prev ] || { echo "no /etc/book4/default-dtb.prev" >&2; exit 1; }
    sudo cp -p /etc/book4/default-dtb.prev /etc/book4/default-dtb
else
    [ -e "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }
    DTS=$(dtc -q -I dtb -O dts "$SRC")   # captured: grep -q in a pipe trips pipefail
    grep -q 'TweeterLeft' <<<"$DTS" || { echo "$SRC has no tweeters?" >&2; exit 1; }
    sudo install -d -m 755 /boot/dtb-test
    sudo dtc -q -I dtb -O dtb -p 8192 -o /boot/dtb-test/four-speakers.dtb "$SRC"
    grep -q four-speakers /etc/book4/default-dtb || sudo cp -p /etc/book4/default-dtb /etc/book4/default-dtb.prev
    echo "$K /dtb-test/four-speakers.dtb" | sudo tee /etc/book4/default-dtb >/dev/null
    echo /dtb-test/camera.dtb | sudo tee /etc/book4/test-dtb >/dev/null
fi
sudo "$HOOK" add "$K"
echo "== default DTB: $(cat /etc/book4/default-dtb)"
sudo grep -E '^menuentry|devicetree' /boot/efi/EFI/fedora/grub.cfg
