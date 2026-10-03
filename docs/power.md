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
[`0002-samsung-emuec-resync-after-system-sleep.patch`](../drivers/anatase/patches/0002-samsung-emuec-resync-after-system-sleep.patch)
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
