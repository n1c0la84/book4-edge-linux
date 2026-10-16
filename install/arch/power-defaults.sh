#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# The suspend settings that are safe as defaults (docs/power.md, 16 October):
#  - pcie_port_pm=force on the kernel command line (both OSes share Fedora's
#    /etc/kernel/cmdline): the Wi-Fi root port may enter D3hot, so the kernel
#    takes the PCIe link to D3cold in suspend and powers the controller off;
#    Wi-Fi comes back by itself ~10 s after resume.
#  - USB controllers may not wake the system (udev rule on Arch and Fedora):
#    otherwise dwc3 keeps every USB PHY, and so the XO vote, on in suspend.
#    USB keyboards/mice can no longer wake the laptop; lid and power key can.
# Not included: the DRIPS DT state (worse with clk/pd_ignore_unused) and the
# forced sync_state (needs the icc_hold debug module).
#
# Run as your user on Arch:  bash install/arch/power-defaults.sh [undo]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
undo=${1:-}
rule=/etc/udev/rules.d/90-book4-usb-nowake.rules
ruletext='# Book4: USB may not wake from suspend, so dwc3 powers its PHYs down (docs/power.md)
ACTION=="bind|change", SUBSYSTEM=="platform", KERNEL=="a[0-9a-f]*.usb", DRIVER=="dwc3-qcom", ATTR{power/wakeup}="disabled"'

sudo -v
if [ "$undo" = undo ]; then
    sudo rm -f "$rule"
else
    printf '%s\n' "$ruletext" | sudo tee "$rule" >/dev/null
fi
sudo udevadm control --reload
sudo udevadm trigger -s platform -a power/wakeup --action=change 2>/dev/null || sudo udevadm trigger -s platform --action=change
echo "Arch: USB wakeup now: $(cat /sys/bus/platform/devices/a*.usb/power/wakeup | tr '\n' ' ')"

inner="set -euo pipefail
rule=$rule
if [ '$undo' = undo ]; then
    sudo rm -f \$rule
    sudo sed -i 's/ pcie_port_pm=force//' /etc/kernel/cmdline
else
    echo $(printf '%s\n' "$ruletext" | base64 -w0) | base64 -d | sudo tee \$rule >/dev/null
    [ -e /etc/kernel/cmdline.prev-power ] || sudo cp -p /etc/kernel/cmdline /etc/kernel/cmdline.prev-power
    grep -qw pcie_port_pm=force /etc/kernel/cmdline || sudo sed -i 's/\$/ pcie_port_pm=force/' /etc/kernel/cmdline
fi
echo \"Fedora cmdline: \$(cat /etc/kernel/cmdline)\"
sudo /etc/kernel/install.d/99-book4-devicetree.install add \"\$(cat /etc/book4/default-kernel)\"
grep -c pcie_port_pm=force /boot/efi/EFI/fedora/grub.cfg | sed 's/^/grub.cfg lines with pcie_port_pm=force: /' || true"
bash "$here/fedora-shell.sh" bash -lc "$inner"
echo "Done. Reboot (normal entry) to use the new kernel option."
