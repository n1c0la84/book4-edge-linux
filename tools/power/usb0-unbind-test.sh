#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# 7.3 sleep test (17 November): on 7.3 the primary USB-C controller
# (a600000.usb) keeps interconnect votes (1-2.5 GB/s) that 7.2 does not have,
# and 7.3 never collapses CX in s2idle. Unbind it, nap 2 min, read the sleep
# log: cxsd > 0 means it was the culprit. The port stops working until
# `bind` or a reboot.
#
#   bash tools/power/usb0-unbind-test.sh          unbind
#   bash tools/power/usb0-unbind-test.sh bind     bind again
set -euo pipefail
d=a600000.usb; drv=/sys/bus/platform/drivers/dwc3-qcom
case ${1:-unbind} in
    unbind) [ -e $drv/$d ] || { echo "$d is not bound"; exit 0; }
            echo $d | sudo tee $drv/unbind >/dev/null; echo "$d unbound: nap 2 min now, wait a minute after waking, then read the sleep log." ;;
    bind)   echo $d | sudo tee $drv/bind >/dev/null; echo "$d bound again" ;;
esac
