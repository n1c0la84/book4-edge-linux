#!/usr/bin/env bash
# Is the Secure Processor (SPSS) running and does it ever sleep? Read-only:
# SMEM sleep stats of every subsystem, twice 20 s apart, plus whether
# TrustZone manages SPSS as PAS image 14. Any boot (EL1 or EL2).
# Run as yourself: bash ~/spss-check.sh
set -euo pipefail
d=$HOME/Projects/book4-edge-linux/tools/power/spss-check
[ $d/spss_check.ko -nt $d/spss_check.c ] || bash $d/build.sh
sudo -v
for i in 1 2; do
  sudo rmmod spss_check 2>/dev/null || true
  n0=$(sudo dmesg | wc -l)
  sudo insmod $d/spss_check.ko
  sudo rmmod spss_check
  echo "== read $i"; sudo dmesg | tail -n +$((n0 + 1)) | grep 'spss_check:' | sed 's/^\[[^]]*\] //'
  [ $i = 1 ] && { echo "(20 s)"; sleep 20; }
done
sudo grep -E "^ *[0-9]+:.*GICv3 384 " /proc/interrupts || echo "SPI 352 (INTID 384): not requested by any Linux driver"
