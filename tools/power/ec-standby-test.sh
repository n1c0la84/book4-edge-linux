#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Board power in sleep (~0.70 W here, 0.11 W in Windows' Modern Standby on
# the same board, SoC collapsed in both): give the EC the standby inputs
# Windows' firmware gives it, together, for one night on battery.
#
# PEP0._DSM in the DSDT (docs/power.md, "DSDT (3 October)") does, per phase:
#   MS:DisplayOff  ECTC.LDOS = 0 (EC 0x89 bit 1)  already 0 under Linux
#                  GIO0.MODS = 0 (TLMM GPIO 44)   low while asleep
#   MS:LPS+        GIO0.HPDC = 1 (TLMM GPIO 49)   high while asleep
#   MS:MS+         ECTC.RESP = 1                  not sent: EC2.sys only logs
#                  and stores it (handler at 0x140001f60, field read nowhere)
# MODS alone (22 October) and LDOS alone changed nothing; HPDC was never
# tried, and never with MODS.
#
# setup: a test UKI = the daily EL2 UKI of the running kernel with GPIO 44
#   freed (gpio-reserved-ranges <35 1>, <44 4> -> <35 1>, <45 3>, as the
#   October el2-mods DTB), a Limine entry for it (via limine-extra.conf;
#   the daily entry stays the default), the sleep hook book4-ec-standby
#   (acts only when GPIO 44 is free, so it is inert on the daily boot), and
#   this repo's book4-sleep-log (tags such sleeps "[el2-mods+hpdc]").
# Then: reboot, pick "EC standby test" in Limine, unplug, close the lid for
# the night. Do not plug or unplug the charger while asleep. Result:
#   journalctl -t book4-sleep -t book4-ec-standby -n 10
# undo: removes the UKI, the entry and the hook (book4-sleep-log stays: it
#   is the packaged one plus the tag).
# The test UKI carries the running kernel; after a kernel update run setup
# again or undo.
#
#   bash tools/power/ec-standby-test.sh [setup|undo|status]
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
rel=$(uname -r)
daily=/boot/EFI/Linux/book4-$rel-el2.efi
test_uki=/boot/EFI/Linux/book4-ecstandby-el2.efi
extra=/etc/book4/limine-extra.conf
hook=/usr/lib/systemd/system-sleep/book4-ec-standby
slog=/usr/lib/systemd/system-sleep/book4-sleep-log
stub=/usr/lib/systemd/boot/efi/linuxaa64.efi.stub
tlmm=/soc@0/pinctrl@f100000
begin='# >>> tools/power/ec-standby-test.sh'
end='# <<< tools/power/ec-standby-test.sh'

drop_entry() {   # remove our block from limine-extra.conf, if any
    [ -e "$extra" ] || return 0
    sudo sed -i "\|^$begin|,\|^$end|d" "$extra"
}

case "${1:-setup}" in
status)
    sudo ls -la "$test_uki" "$hook" 2>&1 | sed 's/^/  /'
    sudo grep -A6 -- "$begin" "$extra" 2>/dev/null | sed 's/^/  /' || echo "  no entry in $extra"
    echo "  booted gpio-reserved-ranges: $(od -A n -t u4 --endian=big /sys/firmware/devicetree/base$tlmm/gpio-reserved-ranges | tr -s ' ')"
    journalctl -t book4-ec-standby -t book4-sleep -n 6 --no-pager 2>/dev/null | sed 's/^/  /'
    exit 0 ;;
undo)
    sudo -v
    sudo rm -f "$test_uki" "$hook" /run/book4-ec-standby
    drop_entry
    sudo book4-boot menu
    echo "Removed the test UKI, its Limine entry and the hook."
    exit 0 ;;
setup) ;;
*) sed -n '3,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 1 ;;
esac

for t in objcopy fdtget fdtput ukify gpioset; do
    command -v $t >/dev/null || { echo "error: $t missing" >&2; exit 1; }
done
sudo -v
sudo test -s "$daily" || { echo "error: no $daily (daily UKI of $rel); sudo book4-boot menu" >&2; exit 1; }

w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
sudo cat "$daily" > "$w/daily.efi"
for s in linux initrd dtb cmdline; do
    objcopy -O binary --only-section=.$s "$w/daily.efi" "$w/$s"
    [ -s "$w/$s" ] || { echo "error: no .$s section in $daily" >&2; exit 1; }
done
r=$(fdtget -t u "$w/dtb" $tlmm gpio-reserved-ranges)
[ "$r" = "35 1 44 4" ] || { echo "error: gpio-reserved-ranges is '$r', expected '35 1 44 4'" >&2; exit 1; }
[ "$(fdtget -ts "$w/dtb" /soc@0/gpu@3d00000/zap-shader status)" = disabled ] ||
    { echo "error: daily DTB is not the EL2 one (zap shader enabled)" >&2; exit 1; }
fdtput -t u "$w/dtb" $tlmm gpio-reserved-ranges 35 1 45 3
echo "DTB: gpio-reserved-ranges 35 1 44 4 -> $(fdtget -t u "$w/dtb" $tlmm gpio-reserved-ranges) (GPIO 44 free)"
cmdline=$(tr -d '\0' < "$w/cmdline")
ukify build --linux "$w/linux" --initrd "$w/initrd" --devicetree "$w/dtb" --cmdline "$cmdline" \
    --stub "$stub" --uname "$rel" --output "$w/test.efi" >/dev/null
sudo install -m 644 "$w/test.efi" "$test_uki"
echo "UKI: $test_uki ($rel, daily command line)"

drop_entry
sudo tee -a "$extra" >/dev/null <<EOF
$begin (EC standby inputs; 'undo' removes this)
/Omarchy ($rel) - EC standby test, MODS + HPDC
    protocol: efi
    resolution: 1024x768
    path: boot():/EFI/Linux/book4-ecstandby-el2.efi
$end
EOF
sudo book4-boot menu

sudo tee "$hook" >/dev/null <<'HOOK'
#!/bin/sh
# Book4 (tools/power/ec-standby-test.sh): the EC's Modern Standby inputs as
# Windows' firmware drives them: GPIO 44 (MODS) low and GPIO 49 (HPDC) high
# while asleep, back to MODS high / HPDC low after. Acts only when the booted
# DTB leaves GPIO 44 free (the test entry); inert on the daily boot.
r=$(od -A n -t u4 --endian=big /sys/firmware/devicetree/base/soc@0/pinctrl@f100000/gpio-reserved-ranges 2>/dev/null | tr -s ' ')
case "$r" in *" 45 3"*) ;; *) exit 0 ;; esac
CHIP=$(for c in /sys/bus/gpio/devices/gpiochip*; do
         [ -e "$c" ] && readlink -f "$c" | grep -q f100000.pinctrl && basename "$c"; done | head -1)
[ -n "$CHIP" ] || exit 0
flag=/run/book4-ec-standby
case "$1" in
pre)
    pkill -f 'gpioset -z -C book4-ecsb' 2>/dev/null
    # held by a daemon through the sleep, so the values cannot fall back
    if gpioset -z -C book4-ecsb -c "$CHIP" 44=0 49=1; then
        touch $flag; logger -t book4-ec-standby "MODS (44) = 0, HPDC (49) = 1 ($1 $2)"
    else
        rm -f $flag; logger -t book4-ec-standby "could not set GPIO 44/49 ($1 $2)"
    fi ;;
post)
    pkill -f 'gpioset -z -C book4-ecsb' 2>/dev/null
    timeout 1 gpioset -c "$CHIP" 44=1 49=0; rc=$?
    [ $rc = 124 ] && logger -t book4-ec-standby "MODS (44) = 1, HPDC (49) = 0 ($1 $2)" ||
        logger -t book4-ec-standby "could not restore GPIO 44/49, rc=$rc" ;;
esac
exit 0
HOOK
sudo chmod 755 "$hook"
cmp -s "$repo/userspace/standby/book4-sleep-log" "$slog" ||
    { sudo install -m 755 "$repo/userspace/standby/book4-sleep-log" "$slog"; echo "book4-sleep-log: repo copy installed (tags +hpdc)"; }
echo "Hook: $hook"
echo
echo "Ready. Reboot, pick \"Omarchy ($rel) - EC standby test, MODS + HPDC\" in Limine,"
echo "unplug, close the lid for the night. Morning: bash $0 status"
