#!/usr/bin/env bash
# qcom_adsp_pwr_lmts v2 (Windows' Modern Standby message from a PM notifier):
# rebuild the sleep kernel's modules and lift the blacklist of the v1.
# Any boot. Run as yourself: bash ~/pwrlmts-v2.sh
# Then: F10 -> "Book4 EL2 (slbounce)" -> "test: el2-sleep", bash ~/el2-drain-test.sh
set -euo pipefail
bash ~/Projects/book4-edge-linux/tools/kernel/build-sleep-modules.sh
modinfo /usr/lib/modules/7.2.7-book4s/extra/qcom_adsp_pwr_lmts.ko | grep -E '^(vermagic|description)'
sudo rm -f /etc/modprobe.d/book4-no-pwrlmts.conf
echo "blacklist lifted; reboot into 'test: el2-sleep' via F10 -> 'Book4 EL2 (slbounce)'"
