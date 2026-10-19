#!/usr/bin/env bash
# Which DSP's sleep votes keep CX up? Variant of "test: el2-sleep" where only
# the ADSP is started by qebspil (no qcom,broken-reset on the CDSP, so the
# CDSP never runs and leaves no votes). GRUB entry "el2-adsponly".
# Any boot. Run as yourself: bash ~/el2-adsponly-prep.sh
# Then: F10 -> "Book4 EL2 (slbounce)" -> "test: el2-adsponly", bash ~/el2-drain-test.sh
set -euo pipefail
repo=$HOME/Projects/book4-edge-linux
cdsp=/soc@0/remoteproc@32300000
bash ~/mount-ro.sh off >/dev/null 2>&1 || true
sudo -v
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
b=$(mktemp -d); sudo mount /dev/sda4 "$b"
cp "$b/dtb-test/book4-sleep-el2.dtb" "$w/in.dtb"
fdtget -l "$w/in.dtb" /soc@0 | grep -qx 'remoteproc@32300000' || { sudo umount "$b"; echo "error: no CDSP node" >&2; exit 1; }
fdtput -d "$w/in.dtb" $cdsp qcom,broken-reset
dtc -q -I dtb -O dtb -p 8192 -o "$w/out.dtb" "$w/in.dtb"
[ -z "$(fdtget -p "$w/out.dtb" $cdsp | grep -x qcom,broken-reset)" ] || { sudo umount "$b"; echo "error: property still there" >&2; exit 1; }
sudo install -m 644 "$w/out.dtb" "$b/dtb-test/book4-sleep-el2-adsponly.dtb"
sync; sudo umount "$b"; rmdir "$b"
bash "$repo/install/arch/test-entry.sh" remove el2-adsponly >/dev/null 2>&1 || true
bash "$repo/install/arch/test-entry.sh" add el2-adsponly -clk_ignore_unused -pd_ignore_unused +id_aa64mmfr0.ecv=1 \
    kernel=/vmlinuz-7.2.7-book4s initrd=/initramfs-7.2.7-book4s-arch.img dtb=/dtb-test/book4-sleep-el2-adsponly.dtb
