#!/usr/bin/env bash
# Run on the "test: drips-noflags" boot, on battery, as yourself:
#   bash ~/drips-sync-run.sh
# Holds an active-only UFS vote (tag=3, dropped by RPMh in sleep; this is what
# made resume work on 15 October), forces every provider's sync_state so the
# firmware's boot votes go away, then one hour of sleep-drain.
set -euo pipefail
repo=$HOME/Projects/book4-edge-linux
ko=$repo/tools/power/icc-hold/icc_hold.ko
[ "$(xxd -p /sys/firmware/devicetree/base/cpus/domain-idle-states/system-sleep-0/arm,psci-suspend-param 2>/dev/null)" = 0200c354 ] \
  || { echo "error: not booted on the DRIPS DTB" >&2; exit 1; }
grep -qw clk_ignore_unused /proc/cmdline && { echo "error: boot 'test: drips-noflags' (clk_ignore_unused is set)" >&2; exit 1; }
sudo -v
grep -q '^icc_hold ' /proc/modules || sudo insmod "$ko" nodes=/soc@0/ufshc@1d84000 tag=3
sudo dmesg | grep 'icc_hold: holding' | tail -1
for p in $(find /sys/devices -name state_synced 2>/dev/null); do
  [ "$(cat "$p")" = 1 ] || printf 1 | sudo tee "$p" >/dev/null   # exactly "1", no newline
done
echo "providers still not synced: $(for p in $(find /sys/devices -name state_synced); do [ "$(cat $p)" = 1 ] || basename "$(dirname $p)"; done | tr '\n' ' ')"
label=drips-synced
wifi=0004:01:00.0; port=0004:00:00.0
if [ "${1:-}" = wifioff ]; then
  # Take the Wi-Fi card off PCI for the sleep (survives since c5-00302, 16 Oct),
  # rescan after resume. Log whether the root port's link actually went down.
  label=drips-wifioff
  linkst() { sudo lspci -vv -s $port | grep -A1 -E 'LnkSta:' | grep -o -E 'Speed [^,]*|DLActive[+-]' | tr '\n' ' '; sudo lspci -vv -s $port | grep -o 'LnkDisable[+-]'; }
  echo "root port before: $(linkst)"
  printf 1 | sudo tee /sys/bus/pci/devices/$wifi/remove >/dev/null; sleep 3
  echo "root port after remove: $(linkst)"
  # Link Disable (LnkCtl bit 4): without a link the host driver powers the
  # controller down in suspend_noirq and re-inits it on resume.
  sudo setpci -s $port CAP_EXP+10.w=0010:0010; sleep 2
  echo "root port after LnkDisable: $(linkst)"
  mark=$(sudo dmesg | wc -l)
  back() {
    echo "== after resume, qcom-pcie messages:"; sudo dmesg | tail -n +$((mark + 1)) | grep -i -E 'qcom-pcie|1c08000|0004:' | head -20
    sudo setpci -s $port CAP_EXP+10.w=0000:0010; sleep 2   # re-enable the link (if still set)
    echo "root port before rescan: $(linkst)"
    printf 1 | sudo tee /sys/bus/pci/devices/$port/rescan >/dev/null
    for i in $(seq 90); do ip -br link | grep -q '^wl' && break; sleep 1; done   # link retrains, hotplug re-adds the card
    echo "Wi-Fi back after ${i} s: $(ip -br link | grep wl || echo 'NONE after 90 s - tell Claude')"
  }
  trap back EXIT
  set -- nowifi-usb
fi
if [ "${1:-}" = full-gdsc ]; then
  # Also collapse the ten USB GDSCs Linux leaves on (RET_ON) during suspend,
  # as Windows' PEP does (tools/power/gdsc-drips, 16 Oct).
  gko=$repo/tools/power/gdsc-drips/gdsc_drips.ko
  grep -q '^gdsc_drips ' /proc/modules || sudo insmod "$gko"
  sudo dmesg | grep 'gdsc_drips' | tail -1
  label=drips-full-gdsc
  set -- full
fi
if [ "${1:-}" = full ]; then
  # Wi-Fi stays: pcie_port_pm=force lets the kernel take the PCIe link to
  # D3cold in suspend by itself (16 Oct). Only USB wakeups go off.
  grep -qw pcie_port_pm=force /proc/cmdline || { echo "error: boot 'test: drips-pcie'" >&2; exit 1; }
  [ "$label" = drips-full-gdsc ] || label=drips-full
  set -- usb-only
fi
if [ "${1:-}" = nowifi ] || [ "${1:-}" = nowifi-usb ] || [ "${1:-}" = usb-only ]; then
  [ "$1" = nowifi ] && label=drips-nowifi
  [ "$1" != usb-only ] && [ -e /sys/bus/pci/devices/$wifi ] && { echo "error: Wi-Fi is present; boot 'test: drips-nowifi'" >&2; exit 1; }
  # USB controllers that may wake keep their PHYs (and the XO vote) on in suspend.
  for w in $(for u in /sys/bus/platform/devices/a*.usb; do find "$u/" -maxdepth 6 -path '*/power/wakeup'; done); do
    printf disabled | sudo tee "$w" >/dev/null
  done
  echo "USB wakeups disabled (wake with the power button or lid)"
fi
sleep 10
bash "$repo/tools/power/sleep-drain.sh" $label
