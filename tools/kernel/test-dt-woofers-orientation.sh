#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Guided test of three changes in one boot (Fedora, GRUB entry
# "alt DT woofer-names.dtb", see docs/handoff-fedora-dt-orientation.md):
#   DT 0005  woofer names by side      (tools/kernel/woofer-names-dtb.sh)
#   DT 0006  eusb5 repeater (0x43) off (same script)
#   emuec experimental 0005  orientation from the CC pin register 0x12
# Asks before each step that needs you; writes everything to
# ~/test-dt-orientation-<date>.log. Run as your user (sudo for the capture).
#
#   bash tools/kernel/test-dt-woofers-orientation.sh
set -uo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
LOG=$HOME/test-dt-orientation-$(date +%Y%m%d-%H%M).log
exec > >(tee "$LOG") 2>&1
DT=/proc/device-tree/soc@0
prop() { tr -d '\0' < "$1" 2>/dev/null || echo "(none)"; }
ask() { read -r -p ">>> $* [Enter] " _ </dev/tty; }
yn() { local a; read -r -p ">>> $* [y/n] " a </dev/tty; echo "    answer: $a"; }
orient() { cat /sys/class/typec/port0/orientation; }

echo "# $(date '+%F %T'), $(uname -r), $(. /etc/os-release; echo "$NAME")"

echo; echo "== 0. which device tree is running"
W0=$(prop $DT/soundwire@6b10000/speaker@0,2/sound-name-prefix)
W3=$(prop $DT/soundwire@6ab0000/speaker@0,2/sound-name-prefix)
R43=$(prop $DT/geniqup@bc0000/i2c@b94000/redriver@43/status)
echo "   SoundWire 0 woofer: $W0   (new DT: SpkrRight)"
echo "   SoundWire 3 woofer: $W3   (new DT: SpkrLeft)"
echo "   repeater 0x43 status: $R43   (new DT: disabled)"
if [ "$W0" = SpkrRight ] && [ "$W3" = SpkrLeft ] && [ "$R43" = disabled ]; then
    echo "   RESULT 0: new DT running"
else
    echo "   RESULT 0: NOT the new DT. Reboot into \"alt DT woofer-names.dtb\"."; exit 1
fi
ls /sys/bus/i2c/devices/ | grep -q '^5-0043$' && echo "   note: 5-0043 still present" || echo "   5-0043 gone (ok)"

echo; echo "== 1. ALSA names"
amixer -c0 scontrols 2>/dev/null | grep -E "'(Spkr|Tweeter)(Left|Right) PA Volume'" | sed 's/^/   /'

echo; echo "== 2. speakers: sides unchanged"
ask "Listen: speaker-test says \"Front Left\" then \"Front Right\". Ready?"
speaker-test -c2 -t wav -l1 >/dev/null 2>&1
yn "Did \"Front Left\" come from the LEFT side and \"Front Right\" from the right?"

echo; echo "== 3. fingerprint (uses the 0x4f repeater, must be unaffected)"
grep -l 1c7a /sys/bus/usb/devices/*/idVendor >/dev/null 2>&1 && echo "   RESULT 3: 1c7a present" || echo "   RESULT 3: 1c7a MISSING"

echo; echo "== 4. orientation with the charger (USB-C port 0)"
ask "Unplug everything from port 0."
ask "Plug the CHARGER into port 0, wait 5 s."
A=$(orient); echo "   charger, first way:   $A"
ask "Unplug it, ROTATE the plug 180 degrees, plug it in again, wait 5 s."
B=$(orient); echo "   charger, rotated:     $B"
if [ "$A" != "$B" ] && [ "$A" != unknown ] && [ "$B" != unknown ]; then
    echo "   RESULT 4: orientation follows the plug (fixed)"
else
    echo "   RESULT 4: orientation does NOT follow the plug ($A / $B)"
fi
ask "Unplug the charger."

echo; echo "== 5. monitor on the hub, both orientations (the capture asks for sudo)"
for way in first rotated; do
    ask "Hub UNPLUGGED, monitor on and connected to the hub. Next: capture, $way orientation."
    # The capture prompts on the terminal and saves its own ~/usbc-dp-<date>.log.
    sudo bash "$REPO/tools/display/usbc-dp-capture.sh" 30 </dev/tty >/dev/tty 2>&1 || true
    C=$(ls -t "$HOME"/usbc-dp-*.log 2>/dev/null | head -1)
    echo "   capture ($way): $C"
    grep -E '\+1s port0|AUX ->|failed to read caps|link training' "$C" | sed 's/^\[[^]]*\] //' | sort | uniq -c | head -8 | sed 's/^/   /'
    yn "Picture on the monitor ($way)?"
    [ $way = first ] && ask "Unplug the hub and ROTATE its plug for the next run."
done

echo; echo "# done; log: $LOG"
