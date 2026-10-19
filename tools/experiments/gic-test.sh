#!/usr/bin/env bash
# On "test: el2-drips": what is pending in the GIC when CPUs come back from
# deep idle during suspend? Builds/loads tools/power/gic-pending (and disables
# the leftover EL1 timers with timer_check disable=1), one probe suspend (wake
# it after ~30 s), then prints the most frequent pending interrupts.
# Run as yourself: bash ~/gic-test.sh [clear [ppi27]]
#   ppi27: also disable and clear PPI 27 (KVM's vtimer) before every deep idle
#   clear: also clear pending-but-disabled interrupts before every deep idle
set -euo pipefail
p=$HOME/Projects/book4-edge-linux/tools/power
grep -q 'id_aa64mmfr0.ecv' /proc/cmdline || { echo "error: boot an EL2 entry (test: el2-drips)" >&2; exit 1; }
[ $p/gic-pending/gic_pending.ko -nt $p/gic-pending/gic_pending.c ] || bash $p/gic-pending/build.sh
[ $p/timer-check/timer_check.ko -nt $p/timer-check/timer_check.c ] || bash $p/timer-check/build.sh
sudo -v
sudo rmmod timer_check 2>/dev/null || true
sudo insmod $p/timer-check/timer_check.ko disable=1
sudo rmmod gic_pending 2>/dev/null || true
sudo insmod $p/gic-pending/gic_pending.ko $([ "${1:-}" = clear ] && echo clear=1) $([[ " $* " == *" ppi27 "* ]] && echo ppi_off=0x08000000)
sudo dmesg | grep 'gic_pending:' | tail -2
bash ~/el2-probe.sh
sudo rmmod gic_pending
sudo rmmod timer_check
sudo dmesg | grep -E 'gic_pending: [0-9]|gic_pending:   |timer_check: [0-9]' | tail -40
sudo grep -E "^ *(3|23|25|26|27|29|30|31):" /proc/interrupts | tr -s ' ' | cut -c1-100 || true
