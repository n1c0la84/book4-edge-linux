#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# EL1 deep-sleep test (docs/TODO.md, CL5/DRIPS item): does the daily sleep
# kernel collapse CX under Qualcomm's hypervisor, as a stock distribution
# boots? The only EL1 test of this kernel (19 October) ran before the VA/WSA
# macro fix (0024/0025) and with qcom_adsp_pwr_lmts crashing the ADSP at
# every suspend, so it does not answer that.
#
# book4-el2-sleep.service only runs at EL2, so at EL1 this does its part by
# hand. Without it the firmware's boot votes stay and nothing can collapse:
#   - icc_hold on UFS (tag 3): releasing the boot votes otherwise breaks UFS
#     on resume
#   - cntv_arm: tick_freeze() disarms CNTV, and under Gunyah APSS did not
#     collapse without it (Burch, XPS 13)
#   - aoss_cxsd_only, as in the daily setup (hourly reset in AOSD)
#   - sync_state forced on every provider
# qcom_adsp_pwr_lmts stays blacklisted (it crashes this ADSP).
#
# The boot entry must not carry clk_ignore_unused / pd_ignore_unused (the
# "el1-book4s" entry of 4 November does). Once, from the daily system:
#   bash install/arch/test-entry.sh add el1-sleep -id_aa64mmfr0.ecv=1 dtb=/dtb-test/book4-sleep.dtb
# Then power on with F10, pick the firmware entry that is NOT "Book4 EL2
# (slbounce)", and in GRUB the entry "... - test: el1-sleep". The screen
# stays black for a while early in boot. If it hangs, hold power.
#
#   bash tools/experiments/el1-sleep-prep.sh          after login, on battery
#   (close the lid for 1 h or more; the sleep log tags the sleep "el1")
#   bash tools/experiments/el1-sleep-prep.sh status   after waking
set -euo pipefail
stats=/sys/kernel/debug/qcom_stats
pd=/sys/kernel/debug/pm_genpd/power-domain-system/idle_states

status() {
    echo "== sleep counters"
    for s in aosd cxsd ddr apss adsp cdsp; do
        printf '   %-5s %s\n' "$s" "$(sudo cat $stats/$s 2>/dev/null | tr '\n' ' ')"
    done
    echo "== system power domain (S0 = SS1, S1 = DRIPS)"
    sudo cat $pd | sed 's/^/   /'
    echo "== providers not synced: $(grep -L 1 $(find /sys/devices -name state_synced) 2>/dev/null | wc -l)"
    echo "== DSPs: $(for r in /sys/class/remoteproc/remoteproc*; do printf '%s=%s ' "$(cat $r/name)" "$(cat $r/state)"; done)"
    # cntv_arm reports how often it armed CNTV only when it is removed
    if [ "${1:-}" = after ]; then
        [ ! -d /sys/module/cntv_arm ] || sudo rmmod cntv_arm
        echo "== $(sudo dmesg | grep 'cntv_arm:' | tail -1)"
    fi
}

[ "$(uname -r)" = 7.2.7-book4s ] || { echo "error: needs the sleep kernel (running $(uname -r))" >&2; exit 1; }
if grep -q 'id_aa64mmfr0.ecv=1' /proc/cmdline || ! journalctl -k -b -o cat | grep -q 'started at EL1'; then
    echo "error: this boot is not at EL1 (see the header for the boot entry)" >&2; exit 1
fi
if grep -qE '(clk|pd)_ignore_unused' /proc/cmdline; then
    echo "error: this entry has clk_ignore_unused/pd_ignore_unused; add the el1-sleep entry (header)" >&2; exit 1
fi
[ -e /sys/firmware/devicetree/base/psci/power-domain-system/domain-idle-states ] ||
    { echo "error: this device tree has no system idle state" >&2; exit 1; }
sudo -v
if [ "${1:-}" = status ]; then status after; exit 0; fi

[ ! -d /sys/module/qcom_adsp_pwr_lmts ] || { echo "error: qcom_adsp_pwr_lmts is loaded (it crashes the ADSP)" >&2; exit 1; }
sudo modprobe icc_hold nodes=/soc@0/ufshc@1d84000 tag=3
sudo dmesg | grep -q 'icc_hold: holding [1-9][0-9]* paths (tag 3)' ||
    { echo "error: icc_hold holds no UFS path; boot votes NOT released" >&2; exit 1; }
sudo modprobe cntv_arm
sudo modprobe aoss_cxsd_only || echo "warning: aoss_cxsd_only did not load: AOSD allowed (hourly reset possible)" >&2
i=0
while [ $i -lt 90 ] && [ ! -e /proc/asound/card0 ]; do sleep 1; i=$((i + 1)); done
[ -e /proc/asound/card0 ] || echo "warning: no sound card after 90 s" >&2
n=0
for p in $(find /sys/devices -name state_synced); do
    [ "$(cat "$p")" = 1 ] || { printf 1 | sudo tee "$p" >/dev/null; n=$((n + 1)); }
done
echo "UFS held, cntv_arm loaded, AOSD $([ -d /sys/module/aoss_cxsd_only ] && echo off || echo allowed), sync_state forced on $n provider(s)"
status
echo
echo "Ready: stop any VM, unplug the charger, close the lid for 1 h or more."
echo "After waking: bash tools/experiments/el1-sleep-prep.sh status"
