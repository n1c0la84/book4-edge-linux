#!/usr/bin/env bash
# EL2 with DSPs, without the USB stick. Run on the NORMAL boot (EL1, not the
# book4s kernel), as yourself: bash ~/el2-dsp-prep.sh
#  1. rebuild the sleep test kernel 7.2.7-book4s (now with Stephan Gerhold's
#     remoteproc attach patches; fresh build, ~20-30 min, lid open);
#  2. rebuild its EL2 DTB (overlay now marks the DSPs qcom,broken-reset) and
#     the GRUB entry "el2-sleep";
#  3. install UEFI Shell + qebspil + slbounce + tcblaunch.exe in
#     \EFI\book4-el2\ and the DSP firmware in \firmware\... on the ESP, and add
#     the firmware boot entry "Book4 EL2 (slbounce)" (boot order unchanged).
# Then: power on with F10, pick "Book4 EL2 (slbounce)", in GRUB "test: el2-sleep".
set -euo pipefail
repo=$HOME/Projects/book4-edge-linux
[ "$(uname -r)" != 7.2.7-book4s ] || { echo "error: boot the normal entry first" >&2; exit 1; }
bash ~/mount-ro.sh off >/dev/null 2>&1 || true
echo "######## 1. kernel"
bash "$repo/tools/kernel/build-sleep-kernel.sh"
echo "######## 2. EL2 DTB + entry"
sudo -v
b=$(mktemp -d); sudo mount /dev/sda4 "$b"; sudo rm -f "$b/dtb-test/book4-sleep-el2.dtb"; sync; sudo umount "$b"; rmdir "$b"
bash "$repo/install/arch/test-entry.sh" remove el2-sleep >/dev/null 2>&1 || true
bash "$repo/install/el2/el2-dtb.sh" /dtb-test/book4-sleep.dtb el2-sleep -clk_ignore_unused -pd_ignore_unused \
    kernel=/vmlinuz-7.2.7-book4s initrd=/initramfs-7.2.7-book4s-arch.img
dtc -q -I dtb -O dts <(sudo sh -c 'b=$(mktemp -d); mount -o ro /dev/sda4 $b; cat $b/dtb-test/book4-sleep-el2.dtb; umount $b; rmdir $b') |
    grep -c 'qcom,broken-reset' | sed 's/^/   DSP nodes with qcom,broken-reset: /'
echo "######## 3. ESP + firmware boot entry"
bash "$repo/install/el2/esp-install.sh"
