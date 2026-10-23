#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Power while awake: what each setting costs, measured on this machine.
# ON BATTERY, screen on, hands off for ~10 minutes (no typing, no mouse: the
# script keeps the screen from dimming or locking while it runs).
#
# For each variant: apply it, wait 20 s, average the battery's power
# (current_now x voltage_now, refreshed by the EC every 2-3 s) over 60 s,
# then put it back. At the end everything is as it was.
#   baseline       as the machine runs now (brightness fixed at 50 % for all
#                  variants except the two brightness ones)
#   wifi-ps        Wi-Fi power saving on (iw ... set power_save on)
#   aspm           PCIe ASPM policy powersupersave (L1 substates for the Wi-Fi link)
#   usb-rpm        runtime PM for the USB controllers and their PHYs (power/control=auto)
#   bright-25      brightness 25 %
#   bright-100     brightness 100 %
#   all-savings    wifi-ps + aspm + usb-rpm together (brightness 50 %)
# Results: printed, and appended to ~/.local/state/book4-awake-power.csv.
#
# Run as yourself:  bash tools/power/awake-test.sh [VARIANT ...]
set -euo pipefail
bat=/sys/class/power_supply/samsung-galaxybook-battery
bl=$(ls -d /sys/class/backlight/* | head -1)
aspm=/sys/module/pcie_aspm/parameters/policy
csv=${XDG_STATE_HOME:-$HOME/.local/state}/book4-awake-power.csv
settle=${SETTLE:-20}; window=${WINDOW:-60}
variants=("$@"); [ ${#variants[@]} -gt 0 ] || variants=(baseline wifi-ps aspm usb-rpm bright-25 bright-100 all-savings)

[ "$(cat $bat/status)" = Discharging ] || { echo "error: unplug the charger first" >&2; exit 1; }
sudo -v

# What we change, and how it was, to put it back.
max=$(cat "$bl/max_brightness"); bright0=$(cat "$bl/brightness")
ps0=$(iw dev wlan0 get power_save 2>/dev/null | awk '{print $NF}')
aspm0=$(sed -n 's/.*\[\(.*\)\].*/\1/p' "$aspm")
usbdevs=$(for d in /sys/bus/platform/devices/*.usb /sys/bus/platform/devices/f[d-f]*.phy; do
    [ -e "$d/power/control" ] && echo "$d"; done)
declare -A usb0; for d in $usbdevs; do usb0[$d]=$(cat "$d/power/control"); done

setb() { echo $(( max * $1 / 100 )) | sudo tee "$bl/brightness" >/dev/null; }
wifips() { sudo iw dev wlan0 set power_save "$1" 2>/dev/null || true; }
setaspm() { echo "$1" | sudo tee "$aspm" >/dev/null 2>&1 || echo "   (ASPM policy not writable)"; }
usbrpm() { for d in $usbdevs; do echo "$1" | sudo tee "$d/power/control" >/dev/null; done; }
restore() {
    echo "$bright0" | sudo tee "$bl/brightness" >/dev/null
    wifips "${ps0:-off}"; setaspm "$aspm0" >/dev/null
    for d in $usbdevs; do echo "${usb0[$d]}" | sudo tee "$d/power/control" >/dev/null; done
}
# Keep the screen on: Omarchy's own idle handling (its "stay awake" toggle),
# put back afterwards; plus a logind inhibitor for sleep and the lid.
awake_file=$HOME/.local/state/omarchy/indicators/stay-awake
awake0=; [ -e "$awake_file" ] && awake0=1
command -v omarchy-toggle-idle >/dev/null && omarchy-toggle-idle stay-awake >/dev/null 2>&1 || true
trap 'restore; [ -n "$awake0" ] || omarchy-toggle-idle allow-idle >/dev/null 2>&1 || true; echo "settings restored"' EXIT

measure() {   # average W over $window s
    local i s=0 n=0 last="" cur
    for ((i = 0; i < window; i++)); do
        cur=$(awk -v i="$(cat $bat/current_now)" -v v="$(cat $bat/voltage_now)" 'BEGIN { printf "%.4f", (i < 0 ? -i : i) / 1e6 * v / 1e6 }')
        s=$(awk -v a=$s -v b=$cur 'BEGIN { print a + b }'); n=$((n + 1))
        sleep 1
    done
    awk -v s=$s -v n=$n 'BEGIN { printf "%.2f", s / n }'
}

apply() {
    setb 50
    case "$1" in
        baseline) ;;
        wifi-ps) wifips on ;;
        aspm) setaspm powersupersave ;;
        usb-rpm) usbrpm auto ;;
        bright-25) setb 25 ;;
        bright-100) setb 100 ;;
        all-savings) wifips on; setaspm powersupersave; usbrpm auto ;;
        *) echo "unknown variant $1" >&2; return 1 ;;
    esac
}
undo() { wifips "${ps0:-off}"; setaspm "$aspm0" >/dev/null; for d in $usbdevs; do echo "${usb0[$d]}" | sudo tee "$d/power/control" >/dev/null; done; }

mkdir -p "$(dirname "$csv")"
[ -e "$csv" ] || echo "time,variant,watts,battery_pct,kernel" > "$csv"
echo "Hands off now: ${#variants[@]} variants x $((settle + window)) s (screen stays on)."
results=()
systemd-inhibit --what=idle:sleep:handle-lid-switch --why="awake power test" sleep $(( ${#variants[@]} * (settle + window) + 30 )) &
inh=$!
for v in "${variants[@]}"; do
    apply "$v"; sleep "$settle"
    w=$(measure)
    printf '   %-12s %s W\n' "$v" "$w"
    results+=("$v $w")
    echo "$(date +%FT%T),$v,$w,$(cat $bat/capacity),$(uname -r)" >> "$csv"
    undo
done
kill $inh 2>/dev/null || true
base=$(printf '%s\n' "${results[@]}" | awk '$1 == "baseline" {print $2}')
if [ -n "$base" ]; then
    echo "== against baseline ($base W):"
    printf '%s\n' "${results[@]}" | awk -v b=$base '$1 != "baseline" { printf "   %-12s %+.2f W\n", $1, $2 - b }'
fi
