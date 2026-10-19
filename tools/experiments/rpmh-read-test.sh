#!/usr/bin/env bash
# On "test: pdc" (rebuilt with rpmh_read): read back every cmd-db resource on
# Linux's RPMh channel (APSS DRV 2), once as booted and once after releasing
# the boot votes (UFS active-only hold + forced sync_state, as el2-probe.sh).
# Anything non-zero after the release that Linux doesn't vote for itself was
# left by the bootloader. Read-only. Any EL; best on the normal EL1 boot.
# Output: ~/src/book4-acpi/linux-state/rpmh-read-TIME/
# Run as yourself: bash ~/rpmh-read-test.sh
set -euo pipefail
echo 'disabled: on 19 Oct the first rpmh_read() hung the whole machine (X1E/this firmware does not answer RPMh reads from the APSS DRV). Do not run.' >&2; exit 1
repo=$HOME/Projects/book4-edge-linux
d=$repo/tools/power/rpmh-read
out=$HOME/src/book4-acpi/linux-state/rpmh-read-$(date +%Y%m%d-%H%M%S); mkdir -p "$out"
grep -q ' rpmh_read$' /proc/kallsyms || { echo "error: this kernel has no rpmh_read(); rebuild the test kernel (tools/kernel/build-pdc-kernel.sh) and boot 'test: pdc'" >&2; exit 1; }
[ $d/rpmh_readall.ko -nt $d/rpmh_readall.c ] || bash $d/build.sh
sudo -v
sudo cat /sys/kernel/debug/cmd-db > "$out/cmd-db.txt" 2>/dev/null || true
[ -s "$out/cmd-db.txt" ] || cp "$(find $HOME/src/book4-acpi/linux-state -name cmd-db.txt -size +1k | head -1)" "$out/cmd-db.txt"
# addresses: ARC/BCM as listed; VRM bases (16-byte aligned) also +4 (enable) and +8 (mode)
addrs=$(awk '/^Slave/{t=$2} /^0x[0-9a-f]+:/{a=strtonum(substr($1,1,length($1)-1)); print a; if (t=="VRM" && a%16==0) {print a+4; print a+8}}' "$out/cmd-db.txt" |
        sort -n -u | awk '{printf "%s0x%x", (NR>1?",":""), $1}')
echo "$(tr ',' '\n' <<<"$addrs" | wc -l) addresses"
readall() {  # $1 = label
  local n0; n0=$(sudo dmesg | wc -l)
  sudo rmmod rpmh_readall 2>/dev/null || true
  sudo insmod $d/rpmh_readall.ko addrs=$addrs
  sudo rmmod rpmh_readall
  sudo dmesg | tail -n +$((n0 + 1)) | grep 'rpmh_readall:' | sed 's/^\[[^]]*\] rpmh_readall: //' > "$out/$1.txt"
  tail -1 "$out/$1.txt"
}
echo "== as booted"; readall booted
grep -q '^icc_hold ' /proc/modules || sudo insmod $repo/tools/power/icc-hold/icc_hold.ko nodes=/soc@0/ufshc@1d84000 tag=3
for p in $(find /sys/devices -name state_synced 2>/dev/null); do
  [ "$(cat "$p")" = 1 ] || printf 1 | sudo tee "$p" >/dev/null
done
sleep 5
echo "== after releasing the boot votes"; readall synced
# name and decode
awk -v OFS='\t' '
  FNR==NR { if ($1 ~ /^Slave/) t=$2; else if ($1 ~ /^0x[0-9a-f]+:$/) { a=strtonum(substr($1,1,length($1)-1)); nm[a]=(a in nm ? nm[a] "/" : "") $2; ty[a]=t } next }
  FILENAME ~ /booted/ { if ($2=="=") b[$1]=$3; next }
  $2=="=" { a=strtonum($1); v=strtonum($3); base=a-a%16; n=nm[a]; t=ty[a]; off=""
            if (n=="") { n=nm[base]; t=ty[base]; off="+" (a-base) }
            dec=""
            if (t=="ARC") dec="level " v
            else if (t=="BCM") dec=sprintf("valid %d x(AB) %d y(IB) %d", int(v/2^29)%2, int(v/2^14)%2^14, v%2^14)
            else if (t=="VRM") dec=(off=="+4" ? "enable " v : off=="+8" ? "mode " v : "value " v)
            printf "%-8s %-22s %-4s %-10s %-10s %s\n", $1, n off, t, b[$1], $3, dec }' \
  "$out/cmd-db.txt" "$out/booted.txt" "$out/synced.txt" > "$out/decoded.txt"
echo
echo "== non-zero after the release (addr, resource, type, as booted, after, decoded):"
awk '$5 != "0x00000000"' "$out/decoded.txt"
echo "saved in $out"
