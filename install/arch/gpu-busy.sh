#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# GPU load and Snapdragon sensors for the Omarchy hardware-monitor widget
# (meviusisback.hw-monitor):
#   ~/.local/bin/book4-gpu-busy + user service book4-gpu-busy: the Adreno's
#        busy share from DRM fdinfo, every 2 s, to
#        $XDG_RUNTIME_DIR/gpu_busy_percent (msm has no sysfs load file)
#   userspace/desktop/hw-monitor-snapdragon.patch on the plugin's hw-probe:
#        CPU temperature from the tsens zones, "Snapdragon X Elite", and the
#        Adreno entry (load from the helper, clock from devfreq, gpuss temp)
# Run as your user (no root):  bash install/arch/gpu-busy.sh
set -euo pipefail
src=$(cd "$(dirname "$0")/../../userspace/desktop" && pwd)
plugin=$HOME/.config/omarchy/plugins/meviusisback.hw-monitor
install -D -m 755 "$src/book4-gpu-busy" "$HOME/.local/bin/book4-gpu-busy"
install -D -m 644 "$src/book4-gpu-busy.service" "$HOME/.config/systemd/user/book4-gpu-busy.service"
systemctl --user daemon-reload
systemctl --user enable --now book4-gpu-busy.service
if [ -d "$plugin" ]; then
    if git -C "$plugin" apply --check "$src/hw-monitor-snapdragon.patch" 2>/dev/null; then
        git -C "$plugin" apply "$src/hw-monitor-snapdragon.patch"; echo "hw-probe patched"
    elif git -C "$plugin" apply --check -R "$src/hw-monitor-snapdragon.patch" 2>/dev/null; then
        echo "hw-probe already patched"
    else
        echo "warning: the patch does not apply to this hw-monitor version" >&2
    fi
    echo "restart the shell (omarchy-restart-shell) to re-run the probe"
fi
sleep 3; echo "GPU busy: $(cat "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gpu_busy_percent") %"
