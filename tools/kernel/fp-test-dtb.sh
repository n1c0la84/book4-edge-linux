#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Test DTB for the fingerprint reader (EgisTec 1c7a:05a1 on usb_2,
# usb@a200000, disabled so far): book4/7.2 (camera + four speakers) plus
# usb_2 in host mode and its eUSB2 PHY behind a repeater. REPEATER=eusb6
# (default: reset on TLMM 184, the GPIO Windows' ACPI gives this controller)
# or eusb5. Commits on branch tmp/fingerprint-$REPEATER, builds the DTB,
# installs it padded as /boot/dtb-test/fingerprint.dtb and makes it the
# GRUB "alt DT" entry (Fedora kernel) via /etc/book4/test-dtb and our hook.
# The normal entries are unchanged. Run in Fedora or through
# install/arch/fedora-shell.sh (sudo asks the Fedora password).
#
# Undo: sudo rm /etc/book4/test-dtb, then rerun the hook
#   (sudo /etc/kernel/install.d/99-book4-devicetree.install add $(cat /etc/book4/default-kernel)).
set -euo pipefail
export GIT_PAGER=cat
TREE=${TREE:-$HOME/src/patchwork}
REF=${REF:-book4/7.2}
REPEATER=${REPEATER:-eusb6}
BR=tmp/fingerprint-$REPEATER
D=arch/arm64/boot/dts/qcom
DTS=$D/x1e80100-samsung-galaxy-book4-edge-14.dts
DTB=x1e80100-samsung-galaxy-book4-edge-14.dtb
HOOK=/etc/kernel/install.d/99-book4-devicetree.install
K=$(cat /etc/book4/default-kernel)
cd "$TREE"
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "Uncommitted changes in $TREE." >&2; exit 1; }
start=$(git branch --show-current)
trap 'git switch -q "$start"' EXIT

echo "== 1. $BR from $REF"
git switch -q -C "$BR" "$REF"
cat >> "$DTS" <<EOF

/* Fingerprint reader (EgisTec 1c7a:05a1) on usb_2. */
&usb_2 {
	dr_mode = "host";

	status = "okay";
};

&usb_2_hsphy {
	vdd-supply = <&vreg_l2e_0p8>;
	vdda12-supply = <&vreg_l3e_1p2>;

	phys = <&${REPEATER}_repeater>;

	status = "okay";
};
EOF
git commit -q -a -m "arm64: dts: qcom: x1e80100-samsung-galaxy-book4-edge-14: enable usb_2 for the fingerprint reader (test, $REPEATER)"
git log --oneline -1

echo "== 2. build the DTB"
make -s LOCALVERSION= olddefconfig >/dev/null
make -s LOCALVERSION= "qcom/$DTB"
ls -l "$D/$DTB"

echo "== 3. install as /boot/dtb-test/fingerprint.dtb (padded for GRUB)"
sudo -v
sudo mkdir -p /boot/dtb-test
sudo dtc -q -I dtb -O dtb -p 8192 -o /boot/dtb-test/fingerprint.dtb "$D/$DTB"
echo "/dtb-test/fingerprint.dtb" | sudo tee /etc/book4/test-dtb >/dev/null

echo "== 4. GRUB entry through the boot hook"
sudo "$HOOK" add "$K"
sudo grep -c cutmem /boot/efi/EFI/fedora/grub.cfg
sudo grep -E '^menuentry' /boot/efi/EFI/fedora/grub.cfg
echo
echo "Reboot, pick \"Fedora Linux ($K) - alt DT fingerprint.dtb\", then: lsusb | grep 1c7a"
