#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
mode=${1:-help}
case "$mode" in
    help|-h|--help)
        echo "Usage: sudo bash $0 check|prepare|baseline|timing|sampled"
        echo "Run prepare once on a fresh el2-drips boot; then baseline, timing, sampled, baseline."
        echo "Each measurement suspends once. Wake manually after about 30 seconds."
        exit 0 ;;
    check|prepare|baseline|timing|sampled) ;;
    *) echo "Unknown mode: $mode" >&2; exit 2 ;;
esac
[[ $# == 1 ]] || { echo "Expected one mode argument." >&2; exit 2; }
[[ $EUID == 0 ]] || { echo "Run with sudo bash $0 $mode" >&2; exit 1; }
die() { echo "error: $*" >&2; exit 1; }
dbg=/sys/kernel/debug
pd=$dbg/pm_genpd/power-domain-system/idle_states
probe=$dbg/book4_psci_probe
dt=/sys/firmware/devicetree/base
bt=/sys/bus/serial/drivers/hci_uart_qca
hold=$repo/tools/power/icc-hold/icc_hold.ko
module=$here/psci_probe.ko
out=
loaded=0
stopped=0
owner=${SUDO_USER:-root}
user_home=$(getent passwd "$owner" | cut -d: -f6)
output_root=${BOOK4_POWER_OUT:-$user_home/src/book4-acpi/linux-state/psci-probe}

finish_probe() {
    if (( loaded )); then
        if (( ! stopped )); then
            if printf 1 > "$probe/stop"; then stopped=1; fi
        fi
        if (( stopped )) && [[ -n $out ]]; then
            cat "$probe/report" > "$out/probe.txt" || true
        fi
        if rmmod psci_probe; then loaded=0; fi
    fi
}
cleanup() {
    local rc=$?
    trap - EXIT
    set +e
    finish_probe
    if [[ -n $out ]]; then
        dmesg > "$out/dmesg-after.txt"
        printf '%s\n' "$rc" > "$out/runner-exit-code.txt"
        chown -R "$owner:$(id -gn "$owner")" "$out"
        echo "Results: $out"
    fi
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

check_module() {
    local file=$1 release
    [[ -f $file ]] || die "Missing $file; run: bash $(dirname "$file")/build.sh"
    release=$(modinfo -F vermagic "$file")
    [[ ${release%% *} == "$(uname -r)" ]] || die "Module/kernel version mismatch: $file"
}

preflight() {
    local log m path flags
    [[ $(uname -m) == aarch64 ]] || die "This test requires arm64."
    [[ -d $dbg/pm_genpd ]] || die "debugfs is not mounted/available at $dbg."
    [[ $(tr '\0' '\n' < "$dt/compatible") == *samsung,galaxy-book4-edge-14* ]] ||
        die "This probe is for the Book4 Edge 14."
    log=$(dmesg)
    grep -q 'All CPU(s) started at EL2' <<< "$log" ||
        die "Boot the el2-drips entry through slbounce; this boot is not confirmed EL2."
    grep -q 'Initialized CPU PM domain topology using OSI mode' <<< "$log" ||
        die "No successful OSI topology initialization in the boot log."
    grep -q '\[s2idle\]' /sys/power/mem_sleep || die "s2idle is not selected."
    if [[ -r /sys/power/pm_test ]]; then
        grep -q '\[none\]' /sys/power/pm_test || die "pm_test must be none."
    fi
    [[ -f $pd ]] || die "Missing PSCI system domain; do not use the flat PC-mode DT."
    [[ $(tr -d '\0' < "$dt/psci/method") == smc ]] || die "Expected PSCI SMC conduit."
    python3 - "$dt" <<'PY'
import pathlib, struct, sys
dt = pathlib.Path(sys.argv[1])
node = dt / "cpus/domain-idle-states/system-sleep-0"
def words(path):
    raw = path.read_bytes()
    return struct.unpack(f">{len(raw)//4}I", raw)
try:
    assert words(node / "arm,psci-suspend-param") == (0x0200c354,)
    phandle, = words(node / "phandle")
    assert phandle in words(dt / "psci/power-domain-system/domain-idle-states")
except (OSError, AssertionError, ValueError, struct.error) as e:
    sys.exit(f"Expected hierarchical DRIPS 0x0200c354 (not 0x4200c354): {e}")
PY
    flags=$(cat /proc/cmdline)
    [[ " $flags " != *" clk_ignore_unused "* && " $flags " != *" pd_ignore_unused "* ]] ||
        die "Boot without clk_ignore_unused/pd_ignore_unused."
    [[ " $flags " == *" pcie_port_pm=force "* ]] || die "Expected pcie_port_pm=force."
    [[ $(cat /sys/devices/system/cpu/online) == 0-11 ]] ||
        die "Keep all 12 CPUs online for this experiment."
    for m in psci_probe timer_check gic_pending gdsc_drips vreg_off spss_check; do
        [[ ! -d /sys/module/$m ]] || die "$m is loaded; reboot for a clean experiment."
    done
    # Unloaded mutating probes can leave state behind: start from a fresh boot.
    for path in "$dbg/tracing/kprobe_events" /sys/kernel/tracing/kprobe_events; do
        if [[ -f $path ]]; then
            [[ -z $(cat "$path") ]] ||
                die "Existing dynamic probes: finish that experiment and reboot first."
        fi
    done
    for path in "$dbg"/qcom_stats/{aosd,cxsd,ddr}; do
        [[ -r $path ]] || die "Missing hardware sleep counter: $path"
    done
}

hold_ok() {
    [[ -d /sys/module/icc_hold ]] || return 1
    [[ $(cat /sys/module/icc_hold/parameters/tag) == 3 &&
       $(cat /sys/module/icc_hold/parameters/nodes) == /soc@0/ufshc@1d84000 &&
       $(cat /sys/module/icc_hold/parameters/all) == N &&
       $(cat /sys/module/icc_hold/parameters/index) == -1 ]] || return 1
    # icc_hold's init currently succeeds even if it acquired zero paths.
    local last
    last=$(dmesg | sed -n '/icc_hold: holding [0-9][0-9]* paths (tag /p' | tail -1)
    [[ $last =~ holding\ [1-9][0-9]*\ paths\ \(tag\ 3\) ]]
}

prepared() {
    local p
    hold_ok || die "Missing verified active-only UFS hold; run prepare first."
    [[ ! -e $bt/serial0-0 ]] || die "Bluetooth is still bound; run prepare first."
    while IFS= read -r -d '' p; do
        [[ $(cat "$p") == 1 ]] || die "Provider not synced: $p; run prepare first."
    done < <(find /sys/devices -name state_synced -print0)
    for p in /sys/bus/platform/devices/a*.usb/power/wakeup; do
        [[ ! -e $p || $(cat "$p") == disabled ]] ||
            die "USB wakeup enabled: $p; run prepare first."
    done
}

preflight
# Check the artifact for the entire sequence, before preparation changes any
# device state or the first baseline is collected. Baseline never loads it.
check_module "$module"
if [[ $mode == check ]]; then
    echo "EL2 boot, OSI initialization, hierarchical 0x0200c354, s2idle and module artifact confirmed."
    echo "This check has not changed hardware or requested suspend."
    exit 0
fi
if [[ $mode == prepare ]]; then
    if [[ ! -d /sys/module/icc_hold ]]; then
        check_module "$hold"
        insmod "$hold" nodes=/soc@0/ufshc@1d84000 tag=3
    fi
    hold_ok || die "UFS hold could not be verified; refusing to release boot votes."
    while IFS= read -r -d '' p; do
        [[ $(cat "$p") == 1 ]] || printf 1 > "$p"
    done < <(find /sys/devices -name state_synced -print0)
    if [[ -e $bt/serial0-0 ]]; then printf serial0-0 > "$bt/unbind"; fi
    for p in /sys/bus/platform/devices/a*.usb/power/wakeup; do
        [[ ! -e $p ]] || printf disabled > "$p"
    done
    prepared
    echo "Prepared: UFS active-only hold, providers synced, Bluetooth unbound, USB wakeups disabled."
    echo "Keep icc_hold loaded throughout the experiment. Reboot to restore the original state."
    exit 0
fi
prepared
mkdir -p "$output_root"
out=$(mktemp -d "$output_root/$(date +%Y%m%d-%H%M%S)-$mode.XXXXXX")
{
    date --iso-8601=seconds
    uname -a
    cat /proc/cmdline /proc/sys/kernel/random/boot_id
    printf 'mode=%s\n' "$mode"
    git -C "$repo" -c safe.directory="$repo" rev-parse HEAD
    git -C "$repo" -c safe.directory="$repo" status --short
    sha256sum "$here"/*.c "$here"/*.sh "$here"/*.py
    if [[ -f $module ]]; then sha256sum "$module"; modinfo "$module"; fi
    if [[ -f $hold ]]; then sha256sum "$hold"; fi
    for p in /sys/module/icc_hold/parameters/*; do
        printf '%s %s\n' "$p" "$(cat "$p")"
    done
} > "$out/metadata.txt"
cat /proc/modules > "$out/modules.txt"
dmesg > "$out/dmesg-before.txt"
cat "$dbg/psci" > "$out/psci-features.txt"
cat /sys/firmware/fdt > "$out/running.dtb"
sha256sum "$out/running.dtb" > "$out/dtb-sha256.txt"
snapshot() {
    local dest=$1 s p wakeup_irq
    mkdir "$dest"
    cat "$pd" > "$dest/system-domain.txt"
    cat /proc/interrupts > "$dest/interrupts.txt"
    cat /sys/power/suspend_stats/{success,fail} > "$dest/suspend-counts.txt"
    # This optional diagnostic returns ENODATA when no wake IRQ was recorded,
    # including before the first suspend. Keep the error without aborting.
    if wakeup_irq=$(cat /sys/power/pm_wakeup_irq 2> "$dest/wakeup-irq-error.txt"); then
        printf '%s\n' "$wakeup_irq" > "$dest/wakeup-irq.txt"
    else
        printf 'unavailable (see wakeup-irq-error.txt)\n' > "$dest/wakeup-irq.txt"
    fi
    for s in aosd cxsd ddr; do cat "$dbg/qcom_stats/$s" > "$dest/$s.txt"; done
    cat "$dbg/clk/clk_summary" > "$dest/clocks.txt"
    if [[ -f $dbg/interconnect/interconnect_summary ]]; then
        cat "$dbg/interconnect/interconnect_summary" > "$dest/interconnect.txt"
    fi
    {
        while IFS= read -r -d '' p; do printf '%s %s\n' "$p" "$(cat "$p")"; done \
            < <(find /sys/devices -name state_synced -print0)
        for p in /sys/bus/platform/devices/a*.usb/power/wakeup; do
            [[ ! -e $p ]] || printf '%s %s\n' "$p" "$(cat "$p")"
        done
    } > "$dest/preparation.txt"
}
snapshot "$out/before"
if [[ $mode != baseline ]]; then
    every=256
    [[ $mode != timing ]] || every=0
    insmod "$module" sample_every="$every"
    loaded=1
    python3 "$here/summarize.py" calibrate "$probe/counter" > "$out/counter-calibration.json"
    cat "$probe/counter" > "$out/counter-before.txt"
fi
ok0=$(cat /sys/power/suspend_stats/success)
fail0=$(cat /sys/power/suspend_stats/fail)
echo "Saving to $out"
echo "Keep the lid open. Suspending in 5 seconds; use the POWER BUTTON after about 30 seconds."
sync
sleep 5
date +%s.%N > "$out/start-wall.txt"
systemctl suspend
complete=0
for ((i=0; i<90; i++)); do
    if [[ $(cat /sys/power/suspend_stats/success) != "$ok0" ||
          $(cat /sys/power/suspend_stats/fail) != "$fail0" ]]; then
        complete=1
        break
    fi
    sleep 1
done
date +%s.%N > "$out/end-wall.txt"
if (( loaded )); then
    cat "$probe/counter" > "$out/counter-after.txt"
    printf 1 > "$probe/stop"
    stopped=1
    cat "$probe/report" > "$out/probe.txt"
    rmmod psci_probe
    loaded=0
fi
snapshot "$out/after"
(( complete )) || die "No completed suspend within 90 awake polling seconds."
[[ $(cat /sys/power/suspend_stats/fail) == "$fail0" ]] ||
    die "Suspend failed; do not interpret this as a sleep measurement."
python3 "$here/summarize.py" report "$out" | tee "$out/summary.txt"
