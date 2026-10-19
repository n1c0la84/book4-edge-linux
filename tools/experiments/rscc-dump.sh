#!/usr/bin/env bash
# Did UEFI leave RPMh votes in the display RSC (DRV 9), which Linux never
# uses? Checks that its register clock is on, dumps its registers read-only,
# and saves cmd-db so the addresses can be named.
# Output: ~/src/book4-acpi/linux-state/rscc-TIME-stageN/
# Run as yourself (EL2 only): bash ~/rscc-dump.sh i-know STAGE   (0, 1, then 3; 2 reset the machine)
set -euo pipefail
# 19 Oct: on the normal boot (EL1, under Gunyah) the first read reset the
# machine (region not mapped for the Linux VM). EL2 only, and only knowingly.
journalctl -k -b -o cat | grep -c 'All CPU(s) started at EL2' >/dev/null || { echo "error: EL2 only (it reset the machine at EL1)" >&2; exit 1; }
[ "${1:-}" = i-know ] || { echo "error: may reset the machine; run as: bash ~/rscc-dump.sh i-know STAGE (0, 1, 3)" >&2; exit 1; }
stage=${2:-0}
case $stage in 0|1|3) ;; *) echo "error: STAGE is 0, 1 or 3 (2 reset the machine)" >&2; exit 1 ;; esac
d=$HOME/Projects/book4-edge-linux/tools/power/rscc-dump
out=$HOME/src/book4-acpi/linux-state/rscc-$(date +%Y%m%d-%H%M%S)-stage${2:-0}; mkdir -p "$out"
[ $d/rscc_dump.ko -nt $d/rscc_dump.c ] || bash $d/build.sh
sudo -v
sudo grep -E "rscc" /sys/kernel/debug/clk/clk_summary | tee "$out/clk.txt"
hw=$(sudo awk '$1=="disp_cc_mdss_rscc_ahb_clk" {for (i=1;i<=NF;i++) if ($i=="Y"||$i=="N"||$i=="?") {print $i; exit}}' /sys/kernel/debug/clk/clk_summary)
[ "$hw" = Y ] || { echo "error: disp_cc_mdss_rscc_ahb_clk is '$hw' in hardware, not reading (would hang the bus)" >&2; exit 1; }
sudo cat /sys/kernel/debug/cmd-db > "$out/cmd-db.txt" 2>/dev/null || true
n0=$(sudo dmesg | wc -l)
sudo rmmod rscc_dump 2>/dev/null || true
echo "reading stage $stage (if the machine resets now, tell Claude: stage $stage reset)"
sync; sleep 1   # a reset loses unsynced files
sudo insmod $d/rscc_dump.ko stage=$stage
sudo rmmod rscc_dump
sudo dmesg | tail -n +$((n0 + 1)) | grep 'rscc_dump:' | sed 's/^\[[^]]*\] //' > "$out/dump.txt"
cat "$out/dump.txt"
# name the RPMh addresses of the TCS commands
if [ "$stage" = 3 ]; then
  db=$out/cmd-db.txt; [ -s "$db" ] || db=$(find $HOME/src/book4-acpi/linux-state -name cmd-db.txt -size +1k | head -1)
  awk 'NR==FNR { if ($1 ~ /^0x[0-9a-f]+:$/) { a=$1; sub(":","",a); n[strtonum(a)] = n[strtonum(a)] " " $2 } next }
       / addr / { for (i=1;i<=NF;i++) if ($i=="addr") { v=strtonum($(i+1)); base=v - v%16; nm=n[v]; if (nm=="") nm=n[base] "+" v-base; print "   " $0 "  <-" nm } }' "$db" "$out/dump.txt"
fi
echo "saved in $out"
