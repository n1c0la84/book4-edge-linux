#!/usr/bin/env bash
# Regulators no Linux driver uses stay at UEFI's last RPMh vote ("unknown"
# state; regulator_late_cleanup skips them). Windows' PEP has these 9 off
# while their devices sleep. Vote them off, then one probe suspend (wake it
# after ~30 s). Best on the normal-boot DRIPS entry ("test: drips-noflags");
# also works on "test: el2-drips". Reboot restores UEFI's votes.
# Run as yourself: bash ~/vreg-off-test.sh
set -euo pipefail
d=$HOME/Projects/book4-edge-linux/tools/power/vreg-off
names=vreg_l1c_1p2,vreg_l1d_0p8,vreg_l1i_1p8,vreg_l2c_0p8,vreg_l3c_0p8,vreg_l3d_1p8,vreg_l6b_1p8,vreg_l8b_3p0,vreg_l9b_2p9
[ $d/vreg_off.ko -nt $d/vreg_off.c ] || bash $d/build.sh
sudo -v
n0=$(sudo dmesg | wc -l)
sudo rmmod vreg_off 2>/dev/null || true
sudo insmod $d/vreg_off.ko names=$names
sudo dmesg | tail -n +$((n0 + 1)) | grep 'vreg_off:' | sed 's/^\[[^]]*\] //'
for r in /sys/class/regulator/regulator.*; do
  case ",$names," in *",$(cat $r/name),"*) echo "  $(cat $r/name): $(cat $r/state)";; esac
done
sleep 3
bash ~/el2-probe.sh
