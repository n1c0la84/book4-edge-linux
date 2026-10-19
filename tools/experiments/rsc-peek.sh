#!/usr/bin/env bash
# Read (never write) what each apps RSC channel has programmed: drv-2 (Linux,
# as a check), then drv-1 and drv-0 (hypervisor / TrustZone). Each runs in its
# own process: if a channel is protected, that process dies with a bus error
# and the next one still runs. Output: ~/src/book4-acpi/linux-state/rsc-peek-TIME.txt
# Run as yourself: bash ~/rsc-peek.sh
set -uo pipefail
out=$HOME/src/book4-acpi/linux-state/rsc-peek-$(date +%Y%m%d-%H%M%S).txt
sudo -v
for d in 2 1 0; do
  echo "== drv-$d"
  sudo ~/src/rsc-peek/rsc-peek $d; rc=$?
  [ $rc = 0 ] || echo "   (exit $rc: $( [ $rc = 135 ] && echo 'bus error: protected' || echo 'failed'))"
done 2>&1 | tee "$out"
echo "saved $out"
