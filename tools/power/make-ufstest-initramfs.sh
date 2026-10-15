#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build a separate Arch initramfs carrying the patched ufs-qcom.ko (from
# build-ufs-patch.sh) and install it as /boot/initramfs-KVER-arch-ufstest.img,
# for a test entry:  install/arch/test-entry.sh add NAME ... initrd=/initramfs-KVER-arch-ufstest.img
# The normal initramfs and the installed modules are not changed: the patched
# module sits in the module tree's updates/ directory only while the image is
# built, and the image is checked to contain it. Run on Arch, as your user.
#
#   bash tools/power/make-ufstest-initramfs.sh
set -euo pipefail
K=$(uname -r)
ko=${BOOK4_POWER_OUT:-$HOME/src/book4-acpi}/modules/ufs-qcom.ko
upd=/usr/lib/modules/$K/updates
img=initramfs-$K-arch-ufstest.img
[ -e "$ko" ] || { echo "error: $ko missing (run build-ufs-patch.sh)" >&2; exit 1; }
[ "$(modinfo -F vermagic "$ko")" = "$(modinfo -F vermagic ufs_qcom)" ] || { echo "error: vermagic mismatch" >&2; exit 1; }
[ ! -e $upd ] || { echo "error: $upd already exists; not touching it" >&2; exit 1; }
if findmnt -rn -S /dev/sda4 >/dev/null; then echo "error: /dev/sda4 (/boot) is mounted; unmount it first" >&2; exit 1; fi

sudo -v
work=$(mktemp -d)
restore() { sudo rm -rf $upd; sudo depmod $K; }
trap 'restore; sudo rm -rf "$work"' EXIT

# 1. Patched module visible to depmod/mkinitcpio only while the image is built.
sudo install -D -m 644 "$ko" $upd/ufs-qcom.ko
sudo depmod $K
[ "$(readlink -f "$(modinfo -n -k $K ufs_qcom)")" = "$(readlink -f $upd/ufs-qcom.ko)" ] ||
    { echo "error: depmod does not prefer updates/" >&2; exit 1; }
sudo mkinitcpio -k $K -g "$work/$img"
restore
echo "== module index restored: ufs_qcom -> $(modinfo -n ufs_qcom)"

# 2. The image must carry the patched module.
mkdir "$work/x"; (cd "$work/x" && sudo lsinitcpio -x "$work/$img")
found=$(sudo find "$work/x" -name 'ufs-qcom.ko*' | head -1)
[ -n "$found" ] && [ "$(sudo modinfo -F srcversion "$found")" = "$(modinfo -F srcversion "$ko")" ] ||
    { echo "error: the patched ufs-qcom.ko is not in the image (found: ${found:-none})" >&2; exit 1; }
echo "== image contains the patched module (${found#$work/x})"

# 3. Install it in /boot under its own name.
b=$(mktemp -d); sudo mount /dev/sda4 "$b"
sudo install -m 644 "$work/$img" "$b/$img"; sync
ls -la "$b/$img"; sudo umount "$b"; rmdir "$b"
echo "== installed /boot/$img"
