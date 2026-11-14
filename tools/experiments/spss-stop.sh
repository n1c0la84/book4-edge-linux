#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Is the Secure Processor (SPSS) what wakes the SoC at each full hour of the
# AOP clock (docs/TODO.md, "Why AOSD resets")? Ask TrustZone to stop it
# (qcom_scm_pas_shutdown(14)), then sleep across a full hour and read the
# sleep log: "CX entries 1" = no visit. Until the next reboot only: UEFI
# starts SPSS again. First do the same sleep WITHOUT this, as the control
# (expect "CX entries 2", the second at N h + 5 s).
#
# Not TrustZone: SPSS is a separate small processor in the SoC with its own
# firmware (RSPU.bin); Linux has no driver for it. Tried once (19 October,
# EL2): the call returned 0 and nothing else changed.
#
#   bash tools/experiments/spss-stop.sh
set -euo pipefail
d=$(cd "$(dirname "$0")/../power/spss-check" && pwd)
{ [ -e "$d/spss_check.ko" ] &&
  [ "$(modinfo -F vermagic "$d/spss_check.ko" | cut -d' ' -f1)" = "$(uname -r)" ]; } || bash "$d/build.sh"
sudo -v
sudo rmmod spss_check 2>/dev/null || true
n0=$(sudo dmesg | wc -l)
sudo insmod "$d/spss_check.ko" shutdown=1
sudo rmmod spss_check
sudo dmesg | tail -n +$((n0 + 1)) | grep 'spss_check: \(SCM\|qcom_scm\)' | sed 's/^\[[^]]*\] //'
s=$(awk -F: '/Last Exited At/{gsub(/ /,"",$2); print $2}' <(sudo cat /sys/kernel/debug/qcom_stats/cxsd))
echo "AOP clock at the last CX exit: $((s / 19200000 / 3600)) h $(((s / 19200000 % 3600) / 60)) min (visits come at each full hour + ~5 s)"
