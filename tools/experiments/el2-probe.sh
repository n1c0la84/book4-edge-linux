#!/usr/bin/env bash
# One probe of a system idle state (works at EL1 or EL2): releases the boot
# votes, unbinds Bluetooth, then one ~30 s suspend, and reports how often the
# system domain was entered, the interrupts during it and the SoC sleep
# counters, plus the PSCI CPU_SUSPEND power_state/return-value histograms.
# Wake it after ~30 s. Results are appended to
#   ~/src/book4-acpi/linux-state/el2-probes.log
# Options (any combination):
#   mods    drive GPIO 44 (MODS, EC "standby" input) low and GPIO 49 (HPDC)
#           high during the suspend, as the Modern Standby _DSM does
#           (needs libgpiod: sudo pacman -S libgpiod)
#   noqsee  unbind the qseecom UEFI app (qcom_qseecom.uefisecapp.0) during the
#           suspend, closing its secure-world session (EL1 only); rebound after
#   lat     also time each system-level CPU_SUSPEND (histogram) and show the
#           last wakeup IRQ (timing only works awake: use with idle)
#   idle    no suspend: display off and 60 s of runtime idle instead
# Run as yourself: bash ~/el2-probe.sh [mods] [lat] [idle]
set -euo pipefail
repo=$HOME/Projects/book4-edge-linux
log=$HOME/src/book4-acpi/linux-state/el2-probes.log
st=/sys/kernel/debug/qcom_stats
sysd=/sys/kernel/debug/pm_genpd/power-domain-system/idle_states
d=/sys/firmware/devicetree/base/cpus/domain-idle-states; dt=$d/system-sleep-0
[ -e $dt ] || dt=$d/domain-sleep-0   # upstream 7.3 name (domain_ss3)
sudo -v
# the test kernel 7.2.7-book4s ships its own icc_hold under extra/
if ! grep -q '^icc_hold ' /proc/modules; then
  if modinfo icc_hold >/dev/null 2>&1; then sudo modprobe icc_hold nodes=/soc@0/ufshc@1d84000 tag=3
  else sudo insmod "$repo/tools/power/icc-hold/icc_hold.ko" nodes=/soc@0/ufshc@1d84000 tag=3; fi
fi
for p in $(find /sys/devices -name state_synced 2>/dev/null); do
  [ "$(cat "$p")" = 1 ] || printf 1 | sudo tee "$p" >/dev/null
done
[ -e /sys/bus/serial/drivers/hci_uart_qca/serial0-0 ] && printf serial0-0 | sudo tee /sys/bus/serial/drivers/hci_uart_qca/unbind >/dev/null
opts=" $* "
gpid=""
restore_opts() {
  [ -n "$gpid" ] && { sudo kill $gpid 2>/dev/null || true; wait $gpid 2>/dev/null || true; }
  if [[ $opts == *" mods "* ]] && [ -n "${chip:-}" ]; then
    sudo timeout 1 gpioset -c "$chip" 44=1 49=0 2>/dev/null || true   # back to "display on"
  fi
  if [[ $opts == *" noqsee "* ]] && [ ! -e /sys/bus/auxiliary/drivers/qcom_qseecom_uefisecapp/qcom_qseecom.uefisecapp.0 ]; then
    printf qcom_qseecom.uefisecapp.0 | sudo tee /sys/bus/auxiliary/drivers/qcom_qseecom_uefisecapp/bind >/dev/null 2>&1 || true
  fi
  if [ -n "${efi_umounted:-}" ] && ! mountpoint -q /sys/firmware/efi/efivars; then
    sudo mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null || true
  fi
  printf serial0-0 | sudo tee /sys/bus/serial/drivers/hci_uart_qca/bind >/dev/null 2>&1 || true
}
trap restore_opts EXIT
extra=""
if [[ $opts == *" mods "* ]]; then
  command -v gpioset >/dev/null || { echo "error: gpioset missing: sudo pacman -S libgpiod" >&2; exit 1; }
  chip=$(for c in /sys/bus/gpio/devices/gpiochip*; do readlink -f "$c" | grep -q f100000.pinctrl && basename "$c"; done | head -1)
  # MS:DisplayOff -> MODS=0, MS:LPS+ -> HPDC=1; gpioset holds the lines until killed
  sudo gpioset -c "$chip" 44=0 49=1 & gpid=$!
  sleep 1; kill -0 $gpid 2>/dev/null || { echo "error: could not drive GPIO 44/49 on $chip" >&2; exit 1; }
  extra+=" mods(GPIO44=0,GPIO49=1)"
fi
if [[ $opts == *" noqsee "* ]]; then
  # Disabled (19 Oct): even with efivarfs unmounted here, services keep it
  # mounted in their own namespaces, so resume still oopses in efivar_lock.
  echo "noqsee is disabled: it crashes the kernel on resume (efivarfs bug)" >&2; exit 1
  d=/sys/bus/auxiliary/drivers/qcom_qseecom_uefisecapp
  # efivarfs resyncs on resume and oopses if its backend is gone
  # (efivarfs_unfreeze_fs -> efivar_lock, 18 Oct): unmount it first.
  if mountpoint -q /sys/firmware/efi/efivars; then sudo umount /sys/firmware/efi/efivars; efi_umounted=1; fi
  [ -e $d/qcom_qseecom.uefisecapp.0 ] && printf qcom_qseecom.uefisecapp.0 | sudo tee $d/unbind >/dev/null
  extra+=" noqsee(efivarfs unmounted, uefisecapp unbound)"
fi
sleep 5
# PC mode (no system power domain): count the per-CPU cpuidle "drips" state
pcstate() { local u=0 r=0 f; for f in /sys/devices/system/cpu/cpu*/cpuidle/state*; do
  [ "$(cat $f/name 2>/dev/null)" = drips ] || continue; u=$((u + $(cat $f/usage))); r=$((r + $(cat $f/rejected))); done; echo "$u $r"; }
# the deepest (last) state of the system domain; 7.2.7-book4s has SS1 + DRIPS
sysd_entries() { if sudo test -e $sysd; then sudo awk 'NR>1{v=$NF} END{print v+0}' $sysd; else pcstate | cut -d' ' -f1; fi; }
cnt() { for s in aosd cxsd ddr; do printf "%s=%s " $s "$(sudo awk '/^Count/{print $2}' $st/$s)"; done; }
snap() { awk 'NR>1 { s=0; for (i=2;i<=NF;i++) if ($i ~ /^[0-9]+$/) s+=$i; else break; print $1, s, $NF }' /proc/interrupts; }
# PSCI: which power_state is passed and what CPU_SUSPEND returns (histograms,
# so millions of calls don't flood the trace buffer).
t=/sys/kernel/tracing
kp=0
if sudo test -w $t/kprobe_events; then
  echo 0 | sudo tee $t/tracing_on >/dev/null
  # leftovers of an interrupted run: disable and drop triggers, then remove
  for e in psci_ret psci_in; do
    d=$t/events/kprobes/$e; sudo test -d $d || continue
    echo 0 | sudo tee $d/enable >/dev/null 2>&1 || true
    sudo grep -v '^#' $d/trigger 2>/dev/null | sed 's/ \[active\]//; s/^/!/' | while read -r tr; do
      echo "$tr" | sudo tee -a $d/trigger >/dev/null 2>&1 || true; done
  done
  sudo test -e $t/events/synthetic/psci_lat && echo '!psci_lat u64 lat_us; s32 ret' | sudo tee -a $t/synthetic_events >/dev/null 2>&1 || true
  echo '-:psci_in' | sudo tee -a $t/kprobe_events >/dev/null 2>&1 || true
  echo '-:psci_ret' | sudo tee -a $t/kprobe_events >/dev/null 2>&1 || true
  # Preferred: one return probe that also reads the entry argument, so state
  # and result land in the same histogram; else two separate probes.
  if echo 'p:psci_in psci_cpu_suspend_enter state=%x0:x32' | sudo tee -a $t/kprobe_events >/dev/null &&
     { echo 'r:psci_ret psci_cpu_suspend_enter state=$arg1:x32 ret=$retval:s32' | sudo tee -a $t/kprobe_events >/dev/null 2>&1 ||
       echo 'r:psci_ret psci_cpu_suspend_enter ret=$retval:s32' | sudo tee -a $t/kprobe_events >/dev/null; }; then
    echo 'hist:keys=state:sort=hitcount' | sudo tee $t/events/kprobes/psci_in/trigger >/dev/null
    if sudo grep -q 'state' $t/events/kprobes/psci_ret/format; then
      echo 'hist:keys=state,ret:sort=hitcount' | sudo tee $t/events/kprobes/psci_ret/trigger >/dev/null
    else
      echo 'hist:keys=ret:sort=hitcount' | sudo tee $t/events/kprobes/psci_ret/trigger >/dev/null
    fi
    if [[ " $* " == *" lat "* ]] && sudo grep -q state $t/events/kprobes/psci_ret/format; then
      # time spent in each system-level CPU_SUSPEND (per CPU), as a log2 histogram
      sysp=$(( 0x$(xxd -p $dt/arm,psci-suspend-param 2>/dev/null || echo 0200c354) ))
      echo 'psci_lat u64 lat_us; s32 ret' | sudo tee -a $t/synthetic_events >/dev/null
      echo "hist:keys=common_cpu:ts0=common_timestamp.usecs if state == $sysp" | sudo tee -a $t/events/kprobes/psci_in/trigger >/dev/null
      echo "hist:keys=common_cpu:lat=common_timestamp.usecs-\$ts0:onmatch(kprobes.psci_in).trace(psci_lat,\$lat,ret) if state == $sysp" | sudo tee -a $t/events/kprobes/psci_ret/trigger >/dev/null
      echo 'hist:keys=lat_us.log2,ret:sort=lat_us' | sudo tee $t/events/synthetic/psci_lat/trigger >/dev/null
      lat=1
    fi
    echo 1 | sudo tee $t/events/kprobes/psci_in/enable $t/events/kprobes/psci_ret/enable >/dev/null
    echo 1 | sudo tee $t/tracing_on >/dev/null
    kp=1
  fi
fi
c0=$(cnt); s0=$(sysd_entries); p0=$(pcstate); snap > /tmp/el2p0.$$
ok0=$(cat /sys/power/suspend_stats/success); fail0=$(cat /sys/power/suspend_stats/fail)
if [[ " $* " == *" idle "* ]]; then
  # No suspend: display off, 60 s of plain runtime idle (clocks keep running)
  echo "display off for 60 s, no suspend: don't touch anything ..."; sleep 2
  hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })' >/dev/null 2>&1 || true
  sleep 60
  hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' >/dev/null 2>&1 || true
  extra+=" idle(display off 60 s, no suspend)"
else
  echo "suspending in 3 s (wake it after ~30 s) ..."; sleep 3
  systemctl suspend
  while [ "$(cat /sys/power/suspend_stats/success)" = "$ok0" ] && [ "$(cat /sys/power/suspend_stats/fail)" = "$fail0" ]; do sleep 1; done
fi
s1=$(sysd_entries); p1=$(pcstate); c1=$(cnt); snap > /tmp/el2p1.$$
{
  echo "== $(date '+%F %T') $(sudo dmesg | grep -m1 -o 'started at EL[12]') system state: $( [ -e $dt ] && echo "$(tr -d '\0' 2>/dev/null < $dt/idle-state-name || basename $dt) 0x$(xxd -p $dt/arm,psci-suspend-param)" || { pc=/sys/firmware/devicetree/base/cpus/idle-states/system-sleep-pc; [ -e $pc ] && echo "PC mode drips 0x$(xxd -p $pc/arm,psci-suspend-param)" || echo 'none in this DT'; })"${extra:+ options:$extra}
  if sudo test -e $sysd; then echo "   system-domain entries during suspend: $((s1 - s0))"
  else echo "   PC mode: cpuidle 'drips' entries during suspend: $(( ${p1% *} - ${p0% *} )), rejected: $(( ${p1#* } - ${p0#* } ))"; fi
  echo "   counters before: $c0"
  echo "   counters after:  $c1"
  echo "   top interrupts during the suspend:"
  awk 'NR==FNR { a[$1]=$2; next } { d = $2 - a[$1]; if (d > 0) print "     " d, $1, $3 }' /tmp/el2p0.$$ /tmp/el2p1.$$ | sort -k1 -rn | head -5
  if [ $kp = 1 ]; then
    echo "   PSCI CPU_SUSPEND power_state passed (hits; includes the awake seconds):"
    sudo grep -E '^\{|Hits' $t/events/kprobes/psci_in/hist | sed 's/^/     /' | head -8
    echo "   PSCI CPU_SUSPEND return values (Linux errno: 0 success, -1 DENIED, -22 INVALID_PARAMS/ADDRESS, -95 NOT_SUPPORTED):"
    sudo grep -E '^\{|Hits' $t/events/kprobes/psci_ret/hist | sed 's/18446744073709551615/-1 (DENIED)/; s/18446744073709551594/-22 (INVALID)/; s/18446744073709551521/-95 (NOT_SUPPORTED)/; s/ -1 }/ -1 (DENIED) }/; s/^/     /' | head -10
    if [ "${lat:-0}" = 1 ]; then
      echo "   time inside the system-level CPU_SUSPEND (log2 us; frozen = 2^-1 in s2idle, so use 'idle'):"
      sudo grep -E '^\{|Hits' $t/events/synthetic/psci_lat/hist | sed 's/^/     /' | head -20
    fi
    echo "   last wakeup IRQ: $(cat /sys/power/pm_wakeup_irq 2>/dev/null || echo none)"
  else
    echo "   (kprobes unavailable: no PSCI return values)"
  fi
} | tee -a "$log"
rm -f /tmp/el2p0.$$ /tmp/el2p1.$$
if [ $kp = 1 ]; then
  echo 0 | sudo tee $t/events/kprobes/psci_in/enable $t/events/kprobes/psci_ret/enable >/dev/null
  echo '!hist:keys=state:sort=hitcount' | sudo tee $t/events/kprobes/psci_in/trigger >/dev/null 2>&1 || true
  echo '!hist:keys=state,ret:sort=hitcount' | sudo tee $t/events/kprobes/psci_ret/trigger >/dev/null 2>&1 || true
  echo '!hist:keys=ret:sort=hitcount' | sudo tee $t/events/kprobes/psci_ret/trigger >/dev/null 2>&1 || true
  if [ "${lat:-0}" = 1 ]; then
    echo '!hist:keys=lat_us.log2,ret:sort=lat_us' | sudo tee $t/events/synthetic/psci_lat/trigger >/dev/null 2>&1 || true
    echo "!hist:keys=common_cpu:lat=common_timestamp.usecs-\$ts0:onmatch(kprobes.psci_in).trace(psci_lat,\$lat,ret) if state == $sysp" | sudo tee -a $t/events/kprobes/psci_ret/trigger >/dev/null 2>&1 || true
    echo "!hist:keys=common_cpu:ts0=common_timestamp.usecs if state == $sysp" | sudo tee -a $t/events/kprobes/psci_in/trigger >/dev/null 2>&1 || true
    echo '!psci_lat u64 lat_us; s32 ret' | sudo tee -a $t/synthetic_events >/dev/null 2>&1 || true
  fi
  echo '-:psci_in' | sudo tee -a $t/kprobe_events >/dev/null 2>&1 || true
  echo '-:psci_ret' | sudo tee -a $t/kprobe_events >/dev/null 2>&1 || true
fi
