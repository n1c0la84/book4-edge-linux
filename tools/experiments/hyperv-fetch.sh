#!/usr/bin/env bash
# Copy Windows' hypervisor and the kernel/HAL that issue PSCI from the Windows
# partition (mounted READ-ONLY by ~/mount-ro.sh) into ~/src/hyperv-re/bin.
# Run as yourself: bash ~/hyperv-fetch.sh
set -euo pipefail
out=$HOME/src/hyperv-re/bin
mkdir -p "$out"
mountpoint -q /mnt/windows || bash ~/mount-ro.sh
w=/mnt/windows/Windows
ls -la $w/System32/hv*.exe $w/System32/hvloader* $w/Boot/EFI/hvloader* 2>/dev/null || true
for f in $w/System32/hv*.exe $w/System32/hvloader.efi $w/System32/hal.dll $w/System32/ntoskrnl.exe \
         $w/System32/kd.dll $w/System32/kdhvcom.dll $w/System32/securekernel.exe $w/System32/hvservice.sys \
         $w/System32/drivers/hvservice.sys $w/System32/drivers/winhvr.sys $w/System32/winhvr.sys; do
  [ -e "$f" ] && cp -v "$f" "$out/" || true
done
# Version info for the record
ls -la "$out"
bash ~/mount-ro.sh off >/dev/null
