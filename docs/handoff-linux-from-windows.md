# Linux handoff: tests from the Windows session (written 8 October in Windows)

The Windows session of 8 October answered the SCDT question and collected
what Windows knows about this machine (14", NP940XMA). This is what is left
to do on Fedora or Arch, quickest and most useful first. Pull first:
`cd ~/book4-edge-linux && git pull --ff-only`. Details are in the linked
sections; tick the TODO items and record results where they point.

What the Windows session settled, for context:

- **Fix B is dead**: Windows never calls `SCDT` / `CableDetect`, awake or in
  Modern Standby ([power.md](power.md#charging-stalls-after-a-plug-in-while-awake-6-7-october-2026)).
  SafiDrv prints all firmware `ADBG` messages to `DbgPrintEx`, so DebugView
  shows them.
- Cycle count is EC **0xD0**, not 0xB6; design/full capacity mapping
  0xB0/0xB2 confirmed ([ec-protocol.md](ec-protocol.md)).
- Windows' sleep reaches hardware low power ~98 % of the time: the Linux
  1.7 W drain is a software problem.
- The USB-C to HDMI hub works in Windows on the same port.

## 1. CPU boost (5 minutes)

Windows on AC: one busy core reaches **~4.0 GHz on CPUs 4-11** (CPUs 0-3 stop
at 3417.6 MHz); all 12 together 3417 MHz; on battery ~2.5 GHz
([TODO](TODO.md), "CPU boost").

```sh
python3 tools/power/cpu-clock.py all          # cross-check the tool: ~3418 on each CPU
cat /sys/devices/system/cpu/cpufreq/policy{0,4,8}/scaling_available_frequencies
echo 1 | sudo tee /sys/devices/system/cpu/cpufreq/boost
cat /sys/devices/system/cpu/cpufreq/policy{4,8}/scaling_max_freq   # above 3417600?
python3 tools/power/cpu-clock.py 4 8           # expect ~4000 on AC
```

If no boost step appears, look at the boot log's `Failed to add opps_by_lvl
at 3417600 for NCC1/NCC2`. Watch temperature (`sensors`) during a longer run.

## 2. HDMI port (5 minutes, never tested)

Monitor on the HDMI port; `cat /sys/class/drm/*/status`,
`dmesg | grep -i 'msm_dp\|hpd'`. In Windows HPD is a GPIO interrupt on
**TLMM 126** (ACPI `_EVT` 0x7E, "HDMI:HPD IN"); our DTB muxes gpio126 to the
DP controller's hardware HPD (`usb2_dp`). If nothing happens, check whether
pin 126 changes on plug-in (`/sys/kernel/debug/gpio`).

## 3. Headset microphone on the jack (5 minutes)

A 4-pole wired headset in the 3.5 mm jack: is there a headset-mic input, does
recording work? ([audio.md](audio.md)). Only if it fails: the Windows audio
driver's jack-mic routing can be looked up in a later Windows session.

## 4. Fingerprint reader (DTS change)

The EgisTec `1c7a:05a1` sits on `usb@a200000` (`usb_2`), disabled in our DTB.
Steps: [handoff-linux-fingerprint.md](handoff-linux-fingerprint.md).

## 5. EC wake timer (enables suspend-then-hibernate)

Decoded from EC2.sys: `{03, T/60, T%60}` (once) / `{02, ...}` (start) /
`{04, 00}` (stop) on the raw target 0x62, T 0-255 in an unknown unit
([ec-protocol.md](ec-protocol.md#wake-timer-raw-target-0x62-decoded-8-october-2026)).

```sh
sudo python3 tools/ec/wake-timer.py once 90 --sleep   # on battery, lid open
```

Wakes after ~90 s: seconds. Nothing after 2-3 min: either minutes (wait for
~90 min) or the EC's wake line is not a wakeup source on Linux; wake with
the power key and record which.

## 6. Charging after an awake plug-in: battery trip point

Windows' only EC write at a plug-in that Linux lacks: `_BTP` writes the
battery trip point to EC RAM **0x91-0x92** (high byte at 0x91), first 0,
then about the remaining capacity in mAh. Probably just an alarm threshold,
but cheap to try: plug in awake (charging stalls), write 0 then the
remaining mAh (EC 0xA2-0xA3) to 0x91-0x92, and measure with
`tools/power/charge-test.sh`. `tools/ec/ectool.py` only reads EC space so
far: add a `write OFF VAL` command first, per the mailbox write in
[ec-protocol.md](ec-protocol.md) (F480 = offset, F481 = value, FF10 = 0x89,
like `SecEne9058KbcWriteEcSpace`). Background:
[power.md](power.md#charging-stalls-after-a-plug-in-while-awake-6-7-october-2026).

## 7. External monitor over USB-C: what Linux does differently

The hub works in Windows (Billboard: DP alt mode 0xFF01, "configured
successfully"). On Linux: `lsusb -v` of the hub's Billboard device
(`bmConfigured`), then the retest already planned in the TODO
(`samsung_emuec` dynamic debug, `drm.debug=0x106`). Windows also makes an
SMC `0x4200010a` (args `1, 0x2a` / `1, 9` / `2, 9`; possibly
`QCOM_SCM_BOOT_SET_REMOTE_STATE`) at display bring-up and teardown; check
whether Linux's DP path does anything similar.

## 8. Keyboard tagged as tablet pad (upstream fix)

Probable cause from the HID caps: the ENE `0cf2:9050`'s System Control
collection has Button usages 1-2, which should show up as BTN_0/BTN_1 on the
merged "Keyboard" node. Confirm with `/proc/bus/input/devices` (KEY bitmap,
bits 0x100/0x101) and the `report_descriptor`; then propose a hwdb entry or
HID quirk ([upstream.md](upstream.md)).

## Still open in Windows (needs the owner)

- Battery below ~80 %: awake plug-in of the 65 W charger, read the charge
  rate (clears or blames the charger).
- One hour lid closed on battery: `powercfg /sleepstudy` for Windows' drain
  rate.
