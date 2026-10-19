#!/usr/bin/env bash
# At EL2 the system power domain is entered ~16 000 times per second during
# s2idle: something brings the CPUs straight back. Diff /proc/interrupts and
# the system domain counter across one short suspend (wake it after ~30 s).
# Output: ~/src/book4-acpi/linux-state/irq-suspend-TIME.txt
# Run as yourself: bash ~/irq-during-suspend.sh
set -euo pipefail
out=$HOME/src/book4-acpi/linux-state/irq-suspend-$(date +%Y%m%d-%H%M%S).txt
sudo -v
sysd=/sys/kernel/debug/pm_genpd/power-domain-system/idle_states
snap() { awk 'NR>1 { s=0; for (i=2;i<=NF;i++) if ($i ~ /^[0-9]+$/) s+=$i; else break; $1=$1; print $1, s, $0 }' /proc/interrupts; }
snap > /tmp/irq0.$$; s0=$(sudo awk 'NR>1{print $NF}' $sysd)
ok0=$(cat /sys/power/suspend_stats/success); fail0=$(cat /sys/power/suspend_stats/fail)
echo "suspending in 3 s (wake it after ~30 s) ..."; sleep 3
systemctl suspend
while [ "$(cat /sys/power/suspend_stats/success)" = "$ok0" ] && [ "$(cat /sys/power/suspend_stats/fail)" = "$fail0" ]; do sleep 1; done
s1=$(sudo awk 'NR>1{print $NF}' $sysd); snap > /tmp/irq1.$$
{
  echo "$(cut -d' ' -f1-12 /proc/cmdline | tr '\n' ' ')"
  echo "system domain s2idle entries during this suspend: $((s1 - s0))"
  echo "interrupts that fired during the suspend (count, irq, description):"
  awk 'NR==FNR { a[$1]=$2; next } { d = $2 - a[$1]; if (d > 0) { $2=""; print d, $0 } }' /tmp/irq0.$$ /tmp/irq1.$$ | sort -rn | head -15
} | tee "$out"
rm -f /tmp/irq0.$$ /tmp/irq1.$$
echo "saved $out"
