#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Daily EL2 deep sleep (docs/power.md, docs/el2.md): what ~/el2-drain-test.sh
# used to set up by hand, done at every EL2 boot of the sleep kernel by a
# systemd service, plus the boot entry and the defaults. Needs the sleep
# kernel (tools/kernel/build-sleep-kernel.sh) and the ESP pieces
# (install/el2/esp-install.sh) first.
#
#   0. GRUB entry "el2-sleep" (install/el2/el2-dtb.sh): the sleep kernel's DTB
#      /dtb-test/book4-sleep.dtb with the EL2 overlay (qcom,broken-reset on
#      the DSPs, so qebspil starts them), without clk/pd_ignore_unused.
#      Re-created every run, so a rebuilt kernel or overlay is picked up.
#   1. book4-el2-sleep.service (only on kernel command lines with
#      id_aa64mmfr0.ecv=1, i.e. the EL2 entries, and only for a kernel that
#      has el1tmr): loads el1tmr (next timer deadline into CNTP_CVAL_EL02 for
#      the firmware), holds the UFS interconnect paths with icc_hold (UFS
#      fails to resume once the boot floors drop otherwise), waits for the
#      sound card, then forces sync_state on every provider (videocc/QCE have
#      no driver here, so it never runs by itself and the boot votes stay).
#   2. qcom_adsp_pwr_lmts blacklisted: its Modern Standby message crashes the
#      Book4's ADSP (Samsung's INF disables it on Windows too).
#   3. EL2 as the default boot, both halves together, because the GRUB
#      default alone would boot the EL2 device tree at EL1 (without slbounce):
#      the firmware entry "Book4 EL2 (slbounce)" first in the boot order
#      (install/el2/esp-install.sh default) and GRUB's default the test entry
#      "el2-sleep" (install/arch/test-entry.sh default). The boot order needs
#      EFI variables, which EL2 does not have: step 3 runs only on an EL1
#      boot; at EL2 the script stops after step 2 and says so.
#
# Run on Arch as your user:  bash install/el2/sleep-setup.sh [undo]
#   undo: removes the service, GRUB's default and (at EL1) the boot order
#   change; the blacklist stays.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
helper=/usr/local/lib/book4/el2-sleep
unit=/etc/systemd/system/book4-el2-sleep.service
blk=/etc/modprobe.d/book4-no-pwrlmts.conf
entry=el2-sleep

[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
if findmnt -rn -S /dev/sda4 >/dev/null; then echo "error: /dev/sda4 (/boot) is mounted; unmount it first" >&2; exit 1; fi
sudo -v

el2=; journalctl -k -b -o cat | grep -c 'All CPU(s) started at EL2' >/dev/null && el2=1

if [ "${1:-}" = undo ]; then
    sudo systemctl disable book4-el2-sleep.service 2>/dev/null || true
    sudo rm -f "$helper" "$unit"
    sudo systemctl daemon-reload
    bash "$repo/install/arch/test-entry.sh" default none
    if [ -z "$el2" ]; then bash "$here/esp-install.sh" default-off
    else echo "EL2 boot: the firmware boot order is unchanged; on EL1 run: bash install/el2/esp-install.sh default-off"; fi
    echo "Removed the service and the GRUB default ($blk kept: the module crashes the ADSP)."
    exit 0
fi

echo "== 0. GRUB entry '$entry'"
bash "$repo/install/arch/test-entry.sh" remove "$entry" >/dev/null 2>&1 || true
# our own generated file (el2-dtb.sh will not overwrite a different one)
b=$(mktemp -d); sudo mount /dev/sda4 "$b"; sudo rm -f "$b/dtb-test/book4-sleep-el2.dtb"
[ -e "$b/vmlinuz-7.2.7-book4s" ] && [ -e "$b/dtb-test/book4-sleep.dtb" ] ||
    { sudo umount "$b"; rmdir "$b"; echo "error: no sleep kernel on /boot; run tools/kernel/build-sleep-kernel.sh" >&2; exit 1; }
sync; sudo umount "$b"; rmdir "$b"
bash "$here/el2-dtb.sh" /dtb-test/book4-sleep.dtb "$entry" -clk_ignore_unused -pd_ignore_unused \
    kernel=/vmlinuz-7.2.7-book4s initrd=/initramfs-7.2.7-book4s-arch.img

echo "== 1. $unit"
sudo mkdir -p "$(dirname "$helper")"
sudo tee "$helper" >/dev/null <<'EOF'
#!/bin/sh
# Book4 (install/el2/sleep-setup.sh): prepare s2idle deep sleep at EL2.
set -eu
modprobe el1tmr
modprobe icc_hold nodes=/soc@0/ufshc@1d84000 tag=3
# Without a verified hold, releasing the boot votes breaks UFS on resume.
dmesg | grep -q 'icc_hold: holding [1-9][0-9]* paths (tag 3)' ||
    { echo "icc_hold holds no UFS path; boot votes NOT released" >&2; exit 1; }
# Release the boot votes after audio has taken its own (ADSP attached, card up).
i=0
while [ $i -lt 90 ] && [ ! -e /proc/asound/card0 ]; do sleep 1; i=$((i + 1)); done
[ -e /proc/asound/card0 ] || echo "no sound card after 90 s; releasing the boot votes anyway" >&2
n=0
for p in $(find /sys/devices -name state_synced); do
    [ "$(cat "$p")" = 1 ] || { printf 1 > "$p"; n=$((n + 1)); }
done
echo "el1tmr loaded, UFS held, sync_state forced on $n provider(s)"
EOF
sudo chmod 755 "$helper"
sudo tee "$unit" >/dev/null <<EOF
# Book4 (install/el2/sleep-setup.sh)
[Unit]
Description=Book4: EL2 deep-sleep setup (el1tmr, UFS hold, release boot votes)
ConditionKernelCommandLine=id_aa64mmfr0.ecv=1
ConditionPathExists=/usr/lib/modules/%v/extra/el1tmr.ko
After=systemd-modules-load.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$helper

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable book4-el2-sleep.service

echo "== 2. $blk"
printf '%s\n' "# book4-edge-linux: its Modern Standby message crashes the ADSP (docs/power.md, 19 Oct)" \
    "blacklist qcom_adsp_pwr_lmts" | sudo tee "$blk" >/dev/null
cat "$blk"

echo "== 3. EL2 as the default boot"
if [ -n "$el2" ]; then
    echo "   EL2 boot: no EFI variables, so the boot order cannot be changed here."
    echo "   The service is active from the next EL2 boot. For the default, run this"
    echo "   script again on an EL1 boot."
    exit 0
fi
entries=$(bash "$repo/install/arch/test-entry.sh" list)   # captured: grep -q in a pipe trips pipefail
grep -qx "# test-entry: $entry" <<<"$entries" ||
    { echo "error: no test entry '$entry'; create it first (docs/el2.md)" >&2; exit 1; }
bash "$here/esp-install.sh" default
bash "$repo/install/arch/test-entry.sh" default "$entry"
echo
echo "Done: power-on starts 'Book4 EL2 (slbounce)', GRUB boots '$entry'. The normal"
echo "(EL1) entries are still in the GRUB menu; F10 at power-on still picks others."
