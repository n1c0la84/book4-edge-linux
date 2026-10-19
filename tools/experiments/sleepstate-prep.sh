#!/usr/bin/env bash
# DSP "sleepstate" SMP2P entries (Windows qcsubsys behaviour): rebuild the
# sleep kernel's modules (adds book4_dsp_sleepstate) and the EL2 DTB of
# "test: el2-sleep" (overlay now has the entries). Any boot; not on
# 7.2.7-book4s at EL2 if you want to keep the running DTB untouched (it is
# only read at boot anyway). Run as yourself: bash ~/sleepstate-prep.sh
# Then: F10 -> "Book4 EL2 (slbounce)" -> "test: el2-sleep", bash ~/el2-drain-test.sh
set -euo pipefail
repo=$HOME/Projects/book4-edge-linux
bash ~/mount-ro.sh off >/dev/null 2>&1 || true
bash "$repo/tools/kernel/build-sleep-modules.sh"
sudo -v
b=$(mktemp -d); sudo mount /dev/sda4 "$b"; sudo rm -f "$b/dtb-test/book4-sleep-el2.dtb"; sync; sudo umount "$b"; rmdir "$b"
bash "$repo/install/arch/test-entry.sh" remove el2-sleep >/dev/null 2>&1 || true
bash "$repo/install/el2/el2-dtb.sh" /dtb-test/book4-sleep.dtb el2-sleep -clk_ignore_unused -pd_ignore_unused \
    kernel=/vmlinuz-7.2.7-book4s initrd=/initramfs-7.2.7-book4s-arch.img
[ -e /etc/modprobe.d/book4-no-pwrlmts.conf ] || bash ~/blacklist-pwrlmts.sh
