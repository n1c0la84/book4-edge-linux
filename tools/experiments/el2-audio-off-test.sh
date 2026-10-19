#!/usr/bin/env bash
# On "test: el2-sleep" with the DSPs attached, ON BATTERY: does Linux's audio
# stack keep CX up through the ADSP? Stops PipeWire, unbinds the sound card,
# the WSA macros, SoundWire and the q6apm DAIs (rx/tx/va macros and wcd938x
# forbid unbinding), leaves the ADSP itself running (battery, USB-C), lists
# the LPASS clocks (q6prm: held on at the ADSP) still on (software counts), then runs
# ~/el2-drain-test.sh.
# Never unbind lpasscc-sc8280xp (direct LPASS clock registers: reading
# clk_summary afterwards faulted and reset the machine, 19 Oct) or
# q6prm-lpass-clock (it would leave the ADSP's clocks on with no owner).
# No sound until reboot. Run as yourself: bash ~/el2-audio-off-test.sh
set -euo pipefail
[ "$(uname -r)" = 7.2.7-book4s ] || { echo "error: boot 'test: el2-sleep'" >&2; exit 1; }
for r in /sys/class/remoteproc/*; do
  [ "$(cat $r/name)" != adsp ] || [ "$(cat $r/state)" = attached ] || [ "$(cat $r/state)" = running ] ||
    { echo "error: the ADSP is not running; this test needs it up" >&2; exit 1; }
done
sudo -v
# Software enable counts only: clk_summary reads the hardware of every clock,
# and once LPASS powers down that read faults and resets the machine (twice,
# 19 Oct).
lpass_clks() {
  local c n
  for c in LPASS_HW_MACRO LPASS_HW_DCODEC LPASS_CLK_ID_TX_CORE_MCLK LPASS_CLK_ID_RX_CORE_TX_MCLK \
           LPASS_CLK_ID_WSA_CORE_TX_MCLK LPASS_CLK_ID_WSA2_CORE_TX_MCLK; do
    n=$(sudo cat /sys/kernel/debug/clk/$c/clk_enable_count 2>/dev/null || echo gone)
    echo "     $c: enable $n"
  done
}
echo "== LPASS clocks on, before:"; lpass_clks

echo "== stop PipeWire"
systemctl --user stop pipewire.socket pipewire-pulse.socket pipewire pipewire-pulse wireplumber 2>/dev/null || true

unbind() {   # driver: unbind every device bound to it
  local d=/sys/bus/$1/drivers/$2 n
  [ -e "$d/unbind" ] || { echo "   $2: cannot be unbound, skipped"; return 0; }
  for n in "$d"/*; do
    [ -L "$n" ] && [ -e "$n/driver" ] || continue
    n=$(basename "$n")
    printf '%s' "$n" | sudo tee "$d/unbind" >/dev/null && echo "   unbound $2 $n" || echo "   FAILED $2 $n"
  done
}
echo "== unbind the audio stack (top-down)"
unbind platform snd-x1e80100
for d in /sys/bus/soundwire/drivers/*; do [ -d "$d" ] && unbind soundwire "$(basename "$d")"; done
for d in wsa_macro qcom-soundwire; do unbind platform $d; done
unbind platform q6apm-dai; unbind platform q6apm-lpass-dais
sleep 10   # runtime-PM autosuspend of the macros that stay bound
echo "== LPASS clocks on, after:"; lpass_clks
echo "   ADSP: $(for r in /sys/class/remoteproc/*; do printf '%s=%s ' $(cat $r/name) $(cat $r/state); done)"
echo
exec bash ~/el2-drain-test.sh
