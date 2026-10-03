# Power: suspend drain

## Result (2 October 2026)

**s2idle draws about 1.7 W on this machine, about 6 % of the battery per
hour.** A full battery lasts roughly 16 hours with the lid closed. This is the
same on the Fedora kernel and the Anatase kernel, and under GNOME and KDE.

An earlier figure of "0.2 W" (1 October, written into this repository) was
**wrong**: it came from reading the battery percentage right after opening the
lid, when the EC had not refreshed it yet. UPower's own history
(`/var/lib/upower/history-charge-*.dat`, readable by root) shows what actually
happened:

| date | kernel | desktop | lid closed | UPower history | rate |
|---|---|---|---|---|---|
| 1 Oct | Fedora 7.2.0-61 | GNOME | 13:13-16:17 (3 h 04 min) | 98 % -> 79 % | ~6 %/h, ~1.7 W |
| 1-2 Oct | Anatase 7.2.7-book4 | KDE Plasma | overnight | 100 % -> empty | same order |
| 2 Oct | Fedora 7.2.0-61 | KDE Plasma | 11:51-12:22 | 50 % -> 47 % | ~6 %/h |
| 2 Oct | Fedora 7.2.0-61 | GNOME | 12:29-12:59 | 52 % -> 45 % | higher, short run |
| 2 Oct | Fedora 7.2.0-61 | KDE Plasma | 13:33-17:30 (3 h 57 min) | 67 % -> 42 % | ~6.3 %/h |
| 2 Oct | Fedora 7.2.0-61 | KDE, **airplane mode** (rfkill Wi-Fi + BT) | 17:35-18:03 | 41 % -> 37 % | ~7 %/h: no better |

Nothing broke on 1 October: the full update, the Anatase kernel and KDE are
all cleared. This is simply how far suspend gets on this machine today.

UPower's live history is readable without root:
`busctl --system --json=short call org.freedesktop.UPower /org/freedesktop/UPower/devices/battery_kb9058_battery org.freedesktop.UPower.Device GetHistory suu charge 21600 500`
(the files in `/var/lib/upower/` are written only now and then).

## Charger plugged in during suspend is not negotiated

On 2 October a charger connected while the lid was closed did not charge for
4 hours. On resume `samsung-emuec 1-0033: failed to clear interrupt: -13`
(five times): the S2MM006 interrupt arrives while the I2C controller is
suspended, and no PD contract is made. Plug chargers in while awake.

Cause, from the driver (3 October): `samsung-emuec` has no suspend/resume
handling. The S2MM006 interrupt is level triggered and not a wake source, so
the core holds it during s2idle and replays it early in resume, before the
I2C controller is back; clearing it and the following sync both fail
(-EACCES), the consumer path is never enabled, and nothing re-checks the port
afterwards. Same on Fedora and Arch (same module).

Fix, **untested and not yet compiled**:
[`0002-samsung-emuec-resync-after-system-sleep.patch`](../drivers/anatase/patches-experimental/0002-samsung-emuec-resync-after-system-sleep.patch)
masks the interrupt across sleep, arms it as a wake source (charger plug-in
wakes the machine to negotiate; logind should suspend again with the lid
closed) and resyncs the port on resume. For the Anatase kernel,
[`install/update-emuec-module.sh`](../install/update-emuec-module.sh) on
Fedora rebuilds only the module from `~/src/patchwork`, then
`install/arch/sync-kernel.sh` carries it to Arch. Test: unplugged, lid
closed, plug in; with the lid still closed it should charge, and on opening
`status` should read Charging without a replug, with a new "PD contract" line
and no `failed to clear interrupt`. Whether the masked interrupt can wake
the system depends on the msm GPIO irqchip; if it cannot, the resume resync
should still start charging when the lid is opened.

### Test of 0002, 3 October (Fedora, Anatase kernel): crash in sleep

Lid closed 16:51 on battery; charger plugged in with the lid closed. The
patched driver **woke the system** (16:54:46), the port resynced (request 1
-110, then 5 V, then **20 V**), no `failed to clear interrupt`, and KDE
**suspended again by itself** (16:54:59) since the lid was closed. Nothing
more was logged: the machine was found rebooting when the lid was opened at
18:35, with no crash record. Suspend on the charger with the previous module
had worked (2 October). Suspect: the 0002 sleep handling (wake-armed level
interrupt) during the second sleep while charging. **0002 rolled back** on
both systems (`.prev` module); the patched module is kept as
`samsung-emuec.ko.0002` for debugging. Next: reproduce with
`pm_debug_messages` and a short second sleep, or try 0002 without
`enable_irq_wake` (resync on resume only).

### v2, 3 October: wake only on an empty port

[`patches-experimental/0002-v2-...`](../drivers/anatase/patches-experimental/0002-v2-samsung-emuec-resync-after-system-sleep.patch)
arms the wake only on a port with nothing attached at suspend; the interrupt
stays masked otherwise and the port is resynced on resume. It covers both
suspects: the wake-armed level line while charging (no longer armed on the
charger's port) and, if the crash repeats with v2, a sleep while charging at
20 V as such (never tested for long before). Each port logs
`suspend: attached=.. wake=..` (dynamic debug). Tested 3 October, Fedora:
plug-in during sleep woke the machine and negotiated 20 V, then it slept
again (charger port `attached=1 wake=0`); one hour asleep while charging
was fine. **Unplugging the charger during sleep crashed it again** (19:56,
nothing logged after `suspend entry`), although no wake was armed on that
port. During sleep v2 leaves the charger's port as the stock driver does
(interrupt not serviced until resume), so the unplug crash may not be ours
at all: next test is the same unplug with the original module.

**Unplug during sleep crashes regardless of our patch** (3 October): same
crash with the original `samsung-emuec` on the Anatase kernel (20:07) and on
the Fedora fallback kernel with its DKMS drivers (`ene-kb9058-battery`
instead of `samsung-galaxybook-ec`, 20:17). Plug-in and charging during
sleep are fine. Not our patch, not the Anatase kernel, not the EC driver.
Remaining suspects: the USB controllers' wake-up (`a600000.usb`,
`a800000.usb` are wakeup-enabled) reacting to the detach, the USB-C side,
or the hardware itself. Until resolved: **open the lid before unplugging.**

Narrowed further the same evening (Anatase kernel, original driver):

- USB controllers' wakeup disabled (`a600000.usb`, `a800000.usb` and all USB
  devices): still crashes.
- **Every wakeup source disabled except the lid and the power key** (14:
  thermal sensors, ADSP/CDSP, USB, Wi-Fi `mhi0`, keyboard `4-0005`, both
  USB-C power supplies, EC battery/AC): still crashes.
- Nothing in EFI pstore after any of these crashes (`efi_pstore` is loaded
  and EFI variables work on this kernel), so no kernel panic was recorded.

So nothing in Linux wakes up for it, and no panic is logged: the machine
resets or loses power below Linux when the power source changes during
s2idle. Next: does Windows survive a charger unplug in Modern Standby? If
it does, the firmware expects something from the OS before sleep (e.g. a
regulator mode or a USB-C/charger setting); if it does not, it is a
platform bug.

**Windows survives it** (the owner never had the problem there). Looked at in
`EC2.sys` on 3 October:

- The `ResillencyPhase` ACPI operation region handler (Modern Standby
  phases) only logs the value and stores it in the device context; nothing
  reads it again and nothing is sent to the EC. Not the missing piece.
- `CableDetect` and `BTPThreshold` handlers do send EC commands (0x0d and
  0x06, value as two bytes).
- `IOCTL_START_WAKEUP` / `_ONCE` / `IOCTL_STOP_WAKEUP` (from a Windows
  service) send an EC command with a timeout (`"TimeOut %d"`): an **EC wake
  timer**. Not related to the unplug crash, but it is how this machine could
  wake itself up from sleep, which the RTC cannot (useful for
  suspend-then-hibernate).

So what Windows does differently is probably not in EC2.sys: candidates are
the ACPI side (the LPS0/PEP Modern Standby notifications in the DSDT, which
Linux on device tree never runs) or the Qualcomm PEP's PMIC configuration
for sleep. Needs the DSDT (`acpidump` in Windows).

## How to measure

- **UPower history** is the most reliable record: timestamped percentage, kept
  across reboots.
- [`tools/power/drain-test.sh`](../tools/power/drain-test.sh) reads
  `charge_now` before and after one lid-closed suspend. The EC refreshes the
  battery values late after resume, so it waits 60 s; still prefer runs of an
  hour or more, and unplug the charger a few minutes before starting.
- Ignore the percentage shown in the first minute after opening the lid.

## What we know about the sleep state

- **The machine stays asleep.** With `pm_debug_messages` on, one suspend of
  five minutes showed a single wake-up, IRQ 131 = `gpio_keys` (the lid), when
  the lid was opened. No wake-up storm.
- `/sys/kernel/debug/qcom_stats` (`aosd`, `cxsd`, `ddr`) read 0 on both
  kernels, before and after suspend, even since boot. Either the SoC never
  reaches those states, or this firmware does not report them; the counters
  alone cannot tell which.
- `EC read failed: -13` during suspend and `hwmon62: parent phy0 should not be
  sleeping` (ath12k) on resume appear on both kernels.
- The RTC cannot wake this machine (`/dev/rtc0 not enabled for wakeup
  events`), so `rtcwake` cannot be used for tests.

Not yet compared with other X1E laptops' figures; if they do much better,
the SoC here probably does not fully power-collapse. Something keeps a vote; candidates are the Wi-Fi (ath12k /
PCIe), the USB controllers (three are wakeup-enabled), the display and the
DSPs.

## Next steps

1. ~~Airplane mode~~: done, no improvement. Switching the radios off with
   rfkill does not help; whether the Wi-Fi PCIe link itself matters is still
   open (unbinding ath12k is avoided on this machine).
2. Unbind devices one at a time before suspending (Wi-Fi, USB, ...) and
   compare.
3. Compare with other X1E machines' reports (Lenovo T14s, Dell XPS 13) and the
   linux-arm-msm list.

In practice: closing the lid is fine for a few hours; for a night on battery,
shut down.
