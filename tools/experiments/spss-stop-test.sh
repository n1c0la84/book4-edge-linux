#!/usr/bin/env bash
# Does the Secure Processor (SPSS, started by UEFI, unattended under Linux)
# block deep sleep? Asks TrustZone to stop it (PAS 14), shows whether its
# interrupt (SPI 352) is still asserted, then one probe suspend (wake it after
# ~30 s). Best on "test: el2-drips"; also works on a normal boot.
# Undo: reboot (UEFI starts SPSS again). Run as yourself: bash ~/spss-stop-test.sh
set -euo pipefail
p=$HOME/Projects/book4-edge-linux/tools/power
for m in spss-check/spss_check gic-pending/gic_pending timer-check/timer_check; do
  [ $p/$m.ko -nt $p/$m.c ] || bash $p/$(dirname $m)/build.sh
done
sudo -v
n0=$(sudo dmesg | wc -l)
sudo rmmod spss_check 2>/dev/null || true
sudo insmod $p/spss-check/spss_check.ko shutdown=1
sudo rmmod spss_check
sudo dmesg | tail -n +$((n0 + 1)) | grep 'spss_check:' | sed 's/^\[[^]]*\] //'
sleep 2
el2=0; grep -q 'id_aa64mmfr0.ecv' /proc/cmdline && el2=1
if [ $el2 = 1 ]; then
  sudo rmmod timer_check gic_pending 2>/dev/null || true
  sudo insmod $p/timer-check/timer_check.ko disable=1
  sudo insmod $p/gic-pending/gic_pending.ko clear=1 ppi_off=0x08000000
  bash ~/el2-probe.sh
  sudo rmmod gic_pending timer_check
  sudo dmesg | grep -E 'gic_pending: [0-9]|gic_pending:   INTID' | tail -8
else
  bash ~/el2-probe.sh
fi
