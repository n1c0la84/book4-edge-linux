#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# USB-C DisplayPort capture: where does the path stop between Alt Mode entry
# (samsung-emuec "configured with pin D") and the display driver (msm_dp)?
# samsung-emuec has no debug messages, so this puts kprobes on its DP steps
# (each VDM read with its register and result, the mux, the HPD work) and on
# the DRM HPD notifications, turns on drm.debug=0x106 for the window, and
# collects the kernel log, Type-C sysfs, DRM connector states and the hub's
# Billboard descriptor. Everything is restored at the end. Read-only towards
# the hardware.
#
#   sudo bash tools/display/usbc-dp-capture.sh [SECONDS]   (default 60)
# Monitor on and connected to the hub; hub unplugged; plug it in when asked.
set -uo pipefail
SECS=${1:-60}
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
OUT=/home/${SUDO_USER:-root}/usbc-dp-$(date +%Y%m%d-%H%M%S).log
T=/sys/kernel/tracing
exec > >(tee "$OUT") 2>&1

state() {
    echo "--- DRM connectors"
    for c in /sys/class/drm/card*-*; do echo "  ${c##*/}: $(cat $c/status 2>/dev/null)"; done
    echo "--- Type-C"
    for p in /sys/class/typec/port*; do
        echo "  ${p##*/}: data_role=$(cat $p/data_role 2>/dev/null) power_role=$(cat $p/power_role 2>/dev/null) orientation=$(cat $p/orientation 2>/dev/null)"
        for a in $p/port*.* $p-partner/*.*; do
            [ -e "$a/svid" ] && echo "    ${a##*/}: svid=$(cat $a/svid) active=$(cat $a/active 2>/dev/null) mode=$(cat $a/mode 2>/dev/null)"
        done
        [ -e $p-partner ] && echo "    partner present"
    done
}

echo "# usbc-dp-capture $(date '+%F %T'), kernel $(uname -r), window ${SECS}s"
state

# kprobes (only if the kernel has kprobe events)
KP=0
if [ -w $T/kprobe_events ]; then
    echo > $T/trace
    {
        echo 'p:book4/vdm samsung_emuec_read_vdm reg=%x1:x16 svid=%x2:x16 cmd=%x3:x8 cmdt=%x4:x8'
        echo 'r:book4/vdm_ret samsung_emuec_read_vdm ret=$retval:s32'
        echo 'p:book4/update_dp samsung_emuec_update_dp'
        echo 'r:book4/set_mux_ret samsung_emuec_set_mux ret=$retval:s32'
        echo 'p:book4/hpd_work samsung_emuec_hpd_work'
        echo 'p:book4/bridge_hpd drm_bridge_hpd_notify status=%x1:u32'
        echo 'p:book4/msm_dp_hpd msm_dp_bridge_hpd_notify status=%x1:u32'
    } | while read -r l; do echo "$l" >> $T/kprobe_events || echo "kprobe failed: $l"; done
    echo 1 > $T/events/book4/enable && KP=1
else
    echo "# no kprobe events in this kernel: kernel log only"
fi
DRMDBG=$(cat /sys/module/drm/parameters/debug 2>/dev/null)
echo 0x106 > /sys/module/drm/parameters/debug 2>/dev/null
cleanup() {
    [ -n "$DRMDBG" ] && echo "$DRMDBG" > /sys/module/drm/parameters/debug
    if [ $KP = 1 ]; then
        echo 0 > $T/events/book4/enable
        grep '^[pr]:book4/' $T/kprobe_events | sed 's/^[pr]:\(book4\/[a-z_]*\).*/-:\1/' | while read -r l; do echo "$l" >> $T/kprobe_events; done
    fi
}
trap cleanup EXIT
SINCE=$(date '+%F %T')

echo
read -r -p ">>> Plug the hub in now (monitor on), then press Enter... " _ </dev/tty
echo "# plugged at $(date +%T); collecting for ${SECS}s"
sleep "$SECS"
state

echo "--- kprobe trace (reg 0xa20 SVID, 0xa40 modes, 0xa60 enter, 0xac0 DP status, 0xae0 configure, 0xaa0 attention; ret 0 = ACK, <0 = none; bridge_hpd status 1 = connected)"
[ $KP = 1 ] && sed -e '/^#/d' $T/trace | head -400
echo "--- kernel log (emuec, typec, msm_dp, hpd, link training)"
journalctl -k --no-pager -o short-monotonic --since "$SINCE" | grep -iE 'emuec|typec|ucsi|msm_dp|dp_|hpd|link|training|aux|billboard|usb [0-9]' | grep -v 'drm_atomic\|plane' | head -300
echo "--- Billboard device"
for d in /sys/bus/usb/devices/*; do
    [ "$(cat $d/bDeviceClass 2>/dev/null)" = 11 ] && { echo "  $d"; lsusb -v -s "$(cat $d/busnum):$(cat $d/devnum)" 2>/dev/null | sed -n '/Billboard/,$p' | head -60; }
done
lsusb
echo "# saved: $OUT"
