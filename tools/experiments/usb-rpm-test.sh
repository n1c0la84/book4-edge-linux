#!/usr/bin/env bash
# The USB controllers never runtime-suspend (power/control = on), so their
# genpd performance vote (CX NOMINAL) stays in force through system suspend
# and CX can never collapse. Allow runtime PM on the dwc3 controllers and
# their xHCI hosts, wait for them to suspend, then run the RPMh trace +
# suspend (rpmh-sleepset.sh). Wake it after ~30 s.
# On the "test: ufsfix-trace" boot. Revert: reboot (nothing is persistent).
# Run as yourself: bash ~/usb-rpm-test.sh
set -euo pipefail
sudo -v
# USB devices first (the fingerprint reader is "on" by default), then the hosts
for d in $(find /sys/bus/platform/devices/a[0-9a-f]*.usb/ -path '*/usb[0-9]*/[0-9]*-[0-9]*' -maxdepth 4 -name '[0-9]*-[0-9]*' 2>/dev/null) \
         /sys/bus/platform/devices/a[0-9a-f]*.usb /sys/bus/platform/devices/a[0-9a-f]*.usb/xhci-hcd.*.auto; do
  [ -e "$d/power/control" ] && printf auto | sudo tee "$d/power/control" >/dev/null
done
if [ "${1:-}" = unbind-fp ]; then
  # The fingerprint reader can't autosuspend (it drops off the bus, see
  # /etc/udev/rules.d/90-book4-fingerprint.rules), which keeps a200000 and its
  # CX vote active. For this test, unbind that controller; reboot restores it.
  [ -e /sys/bus/platform/drivers/dwc3-qcom/a200000.usb ] && printf a200000.usb | sudo tee /sys/bus/platform/drivers/dwc3-qcom/unbind >/dev/null
  echo "a200000.usb unbound (fingerprint reader off until reboot)"
fi
echo "runtime PM allowed; waiting 15 s for the controllers to autosuspend ..."
sleep 15
for d in $(find /sys/bus/platform/devices/a[0-9a-f]*.usb/ -maxdepth 4 -name '[0-9]*-[0-9]*' 2>/dev/null) /sys/bus/platform/devices/a[0-9a-f]*.usb /sys/bus/platform/devices/a[0-9a-f]*.usb/xhci-hcd.*.auto; do
  echo "  ${d#/sys/bus/platform/devices/}: $(cat $d/power/runtime_status)"
done
sudo awk '/^cx  /{p=1} /^cx_ao/{p=0} p && /usb|^cx/' /sys/kernel/debug/pm_genpd/pm_genpd_summary
bash ~/rpmh-sleepset.sh sync
