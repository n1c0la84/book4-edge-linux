#!/usr/bin/env bash
# On "test: sleep" (7.2.7-book4s): load the EL1 timer module and the ADSP
# Modern Standby notifier, check the new kernel's pieces, then one probe
# suspend (wake it after ~30 s), as el2-probe.sh (boot votes released).
# Run as yourself: bash ~/sleep-test.sh
set -euo pipefail
[ "$(uname -r)" = 7.2.7-book4s ] || { echo "error: boot 'test: sleep' (running $(uname -r))" >&2; exit 1; }
sudo -v
echo "== pieces"
l=$(journalctl -k -b -o cat | grep 'qcom-pdc: x1e' || true); echo "   ${l:-(no PDC mode line)}"
d=/sys/firmware/devicetree/base/cpus/domain-idle-states
for n in domain-sleep-1 domain-sleep-0; do
  printf '   %s 0x%s%s\n' $n "$(xxd -p $d/$n/arm,psci-suspend-param 2>/dev/null)" "$([ -e $d/$n/system-sleep-only ] && echo ' system-sleep-only')"
done
for r in VREG_EDP_3P3 VREG_DISPLAY_VDD VREG_OCTA_VDD; do
  for f in /sys/class/regulator/regulator.*; do [ "$(cat $f/name)" = $r ] && echo "   $r: $(cat $f/state) users=$(cat $f/num_users)"; done
done
sudo modprobe cntv_arm && echo "   cntv_arm loaded"
sudo modprobe qcom_adsp_pwr_lmts && echo "   qcom_adsp_pwr_lmts loaded ($(ls /sys/bus/rpmsg/drivers/qcom_adsp_pwr_lmts 2>/dev/null | grep -c PWR_LMTS) channel bound)"
echo "== probe"
bash ~/el2-probe.sh
sudo rmmod cntv_arm && sudo dmesg | grep 'cntv_arm:' | tail -1
