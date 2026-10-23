#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Out-of-memory handling without a swap file (zram only since 24 October):
# systemd-oomd (enabled on Arch, but watching nothing by default) gets the
# user's app.slice, i.e. launched apps and user services like llama-server,
# never session.slice (Hyprland, PipeWire, portals). It kills the app group
# under the most memory pressure (>50 % for 30 s) or the biggest swap user
# (zram 90 % full), before the kernel OOM killer and long thrashing.
# Run as your user (no root):  bash install/arch/oomd.sh [undo]
set -euo pipefail
d=$HOME/.config/systemd/user/app.slice.d
if [ "${1:-}" = undo ]; then
    rm -f "$d/10-book4-oomd.conf"; systemctl --user daemon-reload; echo "removed"; exit 0
fi
install -D -m 644 "$(dirname "$0")/../../userspace/desktop/app-slice-oomd.conf" "$d/10-book4-oomd.conf"
systemctl --user daemon-reload
systemctl is-active --quiet systemd-oomd || echo "warning: systemd-oomd is not running (sudo systemctl enable --now systemd-oomd)" >&2
oomctl | sed -n '/Monitored CGroups/,/Path/p'
