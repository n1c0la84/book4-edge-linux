#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Test kernel with Qualcomm's x1e PDC secondary-mode series and domain_ss3
# from Linux 7.3, and rpmh_read() from linux-next (tools/kernel/pdc-backport/, the same commits as branch
# book4/7.2-pdc in n1c0la84/linux-book4-edge), built from Arch in the
# Fedora container. ~/src/patchwork in Fedora's home is reflink-copied to
# ~/src/patchwork-pdc (instant, shared extents on btrfs), the patches are
# applied there and only the kernel image and the Book4 14" DTB are built:
# the changed drivers (qcom-pdc, pinctrl-msm, pinctrl-x1e80100) are built
# in and the release stays 7.2.7-book4, so the installed modules and
# initramfs still match.
#
# Installs /vmlinuz-7.2.7-book4-pdc and /dtb-test/book4-pdc.dtb on /boot
# (sda4) and adds the GRUB test entry "pdc": normal EL1 boot without
# clk_ignore_unused/pd_ignore_unused. The normal entries are not touched.
#
#   bash tools/kernel/build-pdc-kernel.sh
#
# Undo: bash install/arch/test-entry.sh remove pdc; the two files can stay.
# Delete ~/src/patchwork-pdc in Fedora's home when done.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
rel=7.2.7-book4
dtbname=x1e80100-samsung-galaxy-book4-edge-14.dtb
kimg=/vmlinuz-$rel-pdc
dtb=/dtb-test/book4-pdc.dtb

[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
if findmnt -rn -O ro /mnt/fedora/home >/dev/null; then
    echo "error: /mnt/fedora/home is mounted read-only; unmount it first (the container needs it read-write)" >&2; exit 1
fi
if findmnt -rn -S /dev/sda4 >/dev/null; then
    echo "error: /dev/sda4 (/boot) is mounted; unmount it first" >&2; exit 1
fi
command -v dtc >/dev/null || { echo "error: dtc missing (pacman -S dtc)" >&2; exit 1; }
patches=$(tar -cz -C "$here/pdc-backport" $(cd "$here/pdc-backport" && ls *.patch) | base64 -w0)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

echo "== 1. build in the Fedora container (~/src/patchwork-pdc)"
inner="set -euo pipefail
cd ~/src
if [ ! -e patchwork-pdc ]; then
    echo '   reflink copy ~/src/patchwork -> ~/src/patchwork-pdc' >&2
    cp -a --reflink=always patchwork patchwork-pdc
fi
cd patchwork-pdc
r=\$(make -s LOCALVERSION= kernelrelease)
[ \"\$r\" = $rel ] || { echo \"error: tree release is \$r, expected $rel\" >&2; exit 1; }
p=\$(mktemp -d); echo $patches | base64 -d | tar -xz -C \$p
for f in \$p/*.patch; do
    if patch -p1 -R --dry-run -s -f < \$f >/dev/null 2>&1; then echo \"   already applied: \$(basename \$f)\" >&2
    else patch -p1 --forward -s < \$f >&2; echo \"   applied: \$(basename \$f)\" >&2; fi
done
# modules: incremental, not installed; refreshes Module.symvers so test
# modules can use what the patches export (rpmh_read)
make -s -j\$(nproc) LOCALVERSION= Image modules qcom/$dtbname >&2
grep -q ' qcom_pdc_gic_secondary_set_type\$' System.map || { echo 'error: the PDC series is not in the image' >&2; exit 1; }
grep -q 'rpmh_read' Module.symvers || { echo 'error: rpmh_read not exported' >&2; exit 1; }
[ \"\$(cat include/config/kernel.release)\" = $rel ]
tar -cz -C arch/arm64/boot Image dts/qcom/$dtbname | base64 -w0"
# no suspend while building (a lid close would interrupt the container)
systemd-inhibit --what=sleep:idle:handle-lid-switch --why="kernel build" \
    bash "$repo/install/arch/fedora-shell.sh" bash -lc "$inner" > "$work/out.b64"
base64 -d "$work/out.b64" | tar -xz -C "$work"
[ -s "$work/Image" ] && [ -s "$work/dts/qcom/$dtbname" ] || { echo "error: build output missing" >&2; exit 1; }
dtc -q -I dtb -O dtb -p 8192 -o "$work/book4-pdc.dtb" "$work/dts/qcom/$dtbname"   # padded for GRUB
dtc -q -I dtb -O dts "$work/book4-pdc.dtb" | grep -c 'arm,psci-suspend-param = <0x200c354>' >/dev/null ||
    { echo "error: domain_ss3 missing from the DTB" >&2; exit 1; }

echo "== 2. install $kimg and $dtb on /boot"
sudo -v
b=$(mktemp -d); sudo mount /dev/sda4 "$b"
sudo install -m 644 "$work/Image" "$b$kimg"
sudo mkdir -p "$b/dtb-test"
sudo install -m 644 "$work/book4-pdc.dtb" "$b$dtb"
sync; ls -l "$b$kimg" "$b$dtb"; sudo umount "$b"; rmdir "$b"

echo "== 3. GRUB test entry"
bash "$repo/install/arch/test-entry.sh" remove pdc >/dev/null 2>&1 || true
bash "$repo/install/arch/test-entry.sh" add pdc -clk_ignore_unused -pd_ignore_unused kernel=$kimg dtb=$dtb
echo
echo "Reboot (no slbounce stick), pick 'test: pdc', then:"
echo "  journalctl -k -b | grep -E 'qcom-pdc|PDC'     # which PDC mode the firmware gave us"
echo "  bash ~/el2-probe.sh                            # one suspend, wake it after ~30 s"
