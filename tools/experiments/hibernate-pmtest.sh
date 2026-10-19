#!/usr/bin/env bash
# Find where hibernation resets the machine: run it only up to one stage and
# come straight back (pm_test), with the DSPs stopped first as the real
# hibernation does. Stages, in order:
#   freezer devices platform processors core   (no image written)
#   test_resume   write the image to /swap/swapfile and restore from it at once
# Run one per call, as yourself:  bash ~/hibernate-pmtest.sh STAGE
# If the machine resets, tell Claude which STAGE. Any normal Arch boot.
set -euo pipefail
stage=${1:?STAGE: freezer devices platform processors core test_resume}
case $stage in freezer|devices|platform|processors|core|test_resume) ;; *) echo "unknown stage $stage" >&2; exit 1 ;; esac
sudo -v
# the kernel needs to know the swap file even when no image is written
src=$(findmnt -no SOURCE -T /swap/swapfile | sed 's/\[.*//'); maj=$((0x$(stat -L -c '%t' "$src"))); min=$((0x$(stat -L -c '%T' "$src")))
off=$(sudo btrfs inspect-internal map-swapfile -r /swap/swapfile)
echo "$maj:$min" | sudo tee /sys/power/resume >/dev/null
echo "$off" | sudo tee /sys/power/resume_offset >/dev/null
echo "resume device $maj:$min offset $off"
sudo /usr/local/lib/book4/dsp-ctl stop
trap 'sudo /usr/local/lib/book4/dsp-ctl start; echo none | sudo tee /sys/power/pm_test >/dev/null; echo shutdown | sudo tee /sys/power/disk >/dev/null' EXIT
n0=$(sudo dmesg | wc -l)
if [ "$stage" = test_resume ]; then
  echo none | sudo tee /sys/power/pm_test >/dev/null
  echo test_resume | sudo tee /sys/power/disk >/dev/null
else
  echo "$stage" | sudo tee /sys/power/pm_test >/dev/null
fi
echo "hibernating up to '$stage' (back in ~10 s; if the machine resets, that's the stage) ..."
sync; sleep 2
echo disk | sudo tee /sys/power/state >/dev/null && echo "== back: '$stage' passed" || echo "== '$stage' returned an error"
sudo dmesg | tail -n +$((n0 + 1)) | grep -i -E "PM:|hibernat|error|fail|timeout|Image" | head -30
