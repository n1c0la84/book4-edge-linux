# Power: suspend drain

**Latest reset investigation (3 October evening):** unbinding only the
charging port's `samsung-emuec` before sleep avoids the unplug reset in both
`pm_test=devices` and real s2idle. The tests implicate driver activity or the
USB state it manages, without identifying a faulty function. See
[the test matrix and reproduction scripts](#further-isolation-3-october-evening-charging-port-driver-unbind-succeeds).

## Charging stalls after a plug-in while awake (6-7 October 2026)

Symptom: plugged in while awake, the battery "charges" at ~1 W ("holding"):
stuck at 10 % for an hour on 6 October, on both ports. A brief spike
(~7.5-8 W into the battery) at each plug-in, then almost nothing, while the
laptop draws ~8-9 W: the adapter delivers ~10 W in total despite a 20 V
contract. Later the EC's battery values froze (voltage identical to the
microvolt for 10 minutes) until a reboot.

Pattern over 5-7 October (Arch, patches 0001-0003):

| plug-in | negotiation | result |
|---|---|---|
| lid closed (wake, resync, sleep again), 60 W | only `PD contract 20000 mV` | charged overnight, 58 -> 99 % and to 100 % |
| awake, 65 W (x3, both ports) | `request 1 failed: -110`, then 5 V, then 20 V | stuck at 10 % |
| awake, 60 W | same sequence | unclear (readings frozen) |

When the charger arrives during sleep, the PD firmware has already
negotiated 20 V by itself before the driver looks, so the driver sends no
request. Awake, the driver requests within milliseconds, the S2MM006 has not
settled, the request times out (`samsung_emuec_request_pdo`, 20 x 100 ms),
the port sits at 5 V and our retry (`patches/0001`) gets 20 V a second later.
**Hypothesis:** the EC's battery charger keeps the input limit it set for the
5 V step (~15 W) and does not follow the later 20 V renegotiation. The
charger is probably not at fault (the 60 W one charges on the sleep path;
the 65 W one was only tried awake), not proven.

Workaround: plug the charger in with the lid closed.

0004 installed on Arch (7 October, `pd_grace_ms` 3000): awake plug-in of the
65 W charger now gives `5000 mV` at attach and `20000 mV` 3.1 s later on the
**first** request (no -110, no retry). The 5 V step remains: awake, the
firmware does not raise the contract by itself within 3 s. Whether the
battery now charges is still to be measured. While a charger is connected
the EC does not refresh the battery values at all (identical for minutes,
also on 7 October), so `charge-test.sh` compares before plug-in with after
unplug.

**Fix B, what the DSDT says** (7 October; Fedora's `~/src/acpi/dsdt.dsl`,
the 14" machine's own dump). `EC2.sys` serves vendor operation region
`MCU1` (space `0xA0`, in `\_SB.ECTC`) with four fields: `BTPT`
(`BTPThreshold`, EC command 0x06), **`CBDT` (`CableDetect`, EC command
0x0d)**, `RESP` (Modern Standby phase, logged only) and `PSRC` (read in
the `_Q51`/`_Q52` charger events). The only writer of `CBDT` is
**`Method (SCDT, 1)`** ("set cable detect": logs `SCDT:<value>`, then
`CBDT = Arg0`), and **nothing in the DSDT calls `SCDT`** (nor `SBTP` for
`BTPT`): a Windows driver or service evaluates `\_SB.ECTC.SCDT` directly
with a 32-bit value. Next: find that caller on the Windows partition
(binaries containing `SCDT` / `\_SB.ECTC`, likely a Samsung service or a
Qualcomm charger/UCSI driver) and the value it passes, then try EC command
0x0d with it after an awake plug-in (`tools/ec/`, `charge-test.sh`). Also
in the DSDT: region `EMOP` (space `0x9C`: `DROL`, `PROL`, `CHGS`, `CHTY`,
`CCST`, `HPDS`, `MUXV`, ...: USB-C and charger state) and `BMOP` (space
`0x9E`: `SOC`, `CHST`, `VOLT`, `CHGC`, ...: battery manager), served by
other Windows drivers; the `SCDT` caller probably reads `CHTY`/`CHGS`.
The only EC mailbox call in the DSDT is `CMDD (0xEE, ...)`.

Fix ideas: (A) after attach, give the firmware a grace period (~3 s) to
negotiate on its own and request only if it is still below the best PDO,
so the awake path looks like the sleep path; (B) if not enough, tell the EC
about the contract as Windows does: EC2.sys's `CableDetect` handler sends
EC command `0x0d` (two-byte value), see below.

Test: [`tools/power/charge-test.sh`](../tools/power/charge-test.sh) LABEL
[MINUTES] waits for the plug-in (awake or during sleep), records the
contract and the battery every 10 s and reports capacity gained, average
power into the battery and whether the readings froze. Run below ~80 %:
awake vs. asleep, 60 W vs. 65 W, then again with fix A.

## CPU frequency scaling was off (5 October 2026)

There was **no cpufreq at all** (no `/sys/devices/system/cpu/cpufreq/policy*`):
on X1E the CPU clocks are set by firmware over the SCMI perf protocol, and
the kernel's `scmi-cpufreq.ko` (present in the Anatase build) **has no
autoload alias**, so nothing ever loaded it. Without it the firmware keeps
the cores at its **1.19 GHz** step under any load.

Loaded by hand on Arch (`7.2.7-book4`): three policies (CPUs 0-3, 4-7,
8-11), `scmi` driver, `schedutil`, 710-3417.6 MHz in 13 steps, `boost` 0.
Under load the busy clusters go to 3417.6 MHz and back down when idle.
The boot log's `[Firmware Bug]: Failed to add opps_by_lvl at 3417600 for
NCC1/NCC2` and the `EM: OPP ... is inefficient` lines did not stop it.

| `openssl speed sha256`, 16 KB blocks | with `scmi-cpufreq` | without | |
|---|---|---|---|
| 1 thread | 2 430 MB/s | 846 MB/s | ×2.9 |
| 12 threads (`-multi 12`) | 28 631 MB/s | 11 423 MB/s | ×2.5 |
| idle battery power, 30 s | 5.68 W | 5.68 W | same |

(846/2430 × 3417.6 MHz ≈ 1190 MHz: exactly the firmware's 1190.4 MHz step.)

Fix: [`userspace/modules-load/book4-cpufreq.conf`](../userspace/modules-load/book4-cpufreq.conf)
in `/etc/modules-load.d/`, installed by `install-fedora.sh` and Arch stage 1.
In place on Arch since 5 October; **Fedora still needs it** (same kernel and
modules, so almost certainly also stuck at 1.19 GHz until then).

Power profiles: `power-profiles-daemon` 0.30 has only its `placeholder`
backend here (no `intel_pstate`/`amd_pstate`, no ACPI platform profile), so
switching profiles (Omarchy menu, `powerprofilesctl`) changes nothing. The
Samsung EC does register a platform profile, `samsung-galaxybook`
(`quiet balanced performance`, `/sys/class/platform-profile/platform-profile-0`),
that nothing uses yet.

Tested 5 October (Arch, on battery, `scmi-cpufreq` loaded): 60 s of
`openssl speed -bytes 16384 -multi 12 sha256` per profile, 60 s rest between.

| profile | MB/s | clocks under load | power under load | CPU temp start -> peak |
|---|---|---|---|---|
| quiet | 29 019 | 3417 MHz, all clusters, whole minute | ~37-40 W | 42 -> 85 C |
| balanced | 29 030 | same | ~37-40 W | 46 -> 91 C |
| performance | 28 942 | same | ~39-44 W | 53 -> 96 C |

No measurable difference: same throughput, no throttling in any profile,
the same temperature rise during each run (+23 C in 50 s); the rising peaks
follow the starting temperature (60 s rest was not enough). The battery
current refreshes only every 10-20 s, so the power column is coarse. The fan
was a little louder at the end, consistent with the accumulated heat.
**Left as is**: not wired to the profile switch. A longer run (minutes per
profile, full cool-down) could still show a difference near the thermal
limit or in the fan curve.

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

Initial experimental patch (subsequently tested and superseded by v2 below):
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

### DSDT (3 October): what Windows does at Modern Standby

`PEP0` (`QCOM0C17`) `_DSM` with the Microsoft Modern Standby UUID
`11e00d56-ce64-47ce-837b-1f898f9aa461`:

| notification | firmware action |
|---|---|
| 3 `MS:DisplayOff` | `ECTC.LDOS = 0` (EC 0x89 bit 1), `GIO0.MODS = 0` (**TLMM GPIO 44**) |
| 4 `MS:DisplayOn` | `ECTC.LDOS = 1`, `GIO0.MODS = 1` |
| 5 `MS:LPS+` | `GIO0.HPDC = 1` (TLMM GPIO 49) |
| 7 / 8 `MS:MS+` / `MS:MS-` | `ECTC.RESP = 1 / 0` (logged only by EC2.sys) |

Linux on device tree runs none of this. Anatase's DTS also reserves GPIOs
44-47, so Linux cannot drive 44 at all.

Tests (Anatase kernel, original `samsung-emuec`):

1. **LDOS only** ([patches-experimental/0003](../drivers/anatase/patches-experimental/0003-samsung-galaxybook-ec-display-off-during-sleep.patch),
   EC write 0x89 added to `samsung-galaxybook-ec`): the EC accepts the write,
   but the bit was already 0 under Linux (never set), so nothing changed.
   Still resets.
2. **GPIO 44 freed** (DTB with `gpio-reserved-ranges = <35 1>, <45 3>`, boots
   fine, so 44 is not secure-protected) and driven low before sleep / high
   after by a systemd-sleep hook ([userspace/standby/book4-mods](../userspace/standby/book4-mods)).
   **Behaviour changes**: after the unplug the blue charge LED goes **off**
   (it stayed **on** in every earlier crash, so the EC had not handled the
   unplug). The machine still reset, apparently **when the lid was opened**,
   i.e. on resume rather than at the unplug.

MODS is clearly the EC's "system in standby" input. The remaining reset looks
like a resume problem after a power-source change during sleep.

Narrowing it down (same evening, gpio44 DTB, original `samsung-emuec`):

| during sleep | wake up on | result |
|---|---|---|
| nothing | battery | fine (every night) |
| plug in | charger | fine (with 0002 v2) |
| unplug, plug back in | charger | **fine** |
| unplug | **battery** | **reset** |

With journald syncing every second
([tools/power/journal-sync.sh](../tools/power/journal-sync.sh)) and PM
debug messages on, the last line on disk was systemd freezing the user
slices before suspend; **nothing from the resume reached the disk**, not even
`PM: suspend exit`. The reset happens during the kernel's own resume or
within about a second of it, before userspace runs.

Still open, two candidates: something in the early kernel resume (power
domains, the first drivers) when the power source changed during sleep, or a
hardware brownout at that moment. Next step: a kernel with
`CONFIG_PSTORE_CONSOLE` and a DTB with a `ramoops` reserved-memory region
(free RAM between `0xe36a0000` and `0xff800000` in the current map), so the
last console lines survive a warm reset; an empty region would point to a
power cut instead.

Until then: **open the lid before unplugging the charger.**

Test material: [install/gpio44-test.sh](../install/gpio44-test.sh) (separate
GRUB entry with GPIO 44 freed + the sleep hook),
[tools/power/allwake-off.sh](../tools/power/allwake-off.sh).

## Further isolation, 3 October evening: charging-port driver unbind succeeds

On Arch, `7.2.7-book4`, installed `samsung-emuec` without suspend/resume
callbacks, and no `book4-mods` hook:

| test | charger action | result |
|---|---|---|
| Real s2idle, lid open, power-button wake | unplug during sleep | automatic reset |
| Real s2idle | unplug, reconnect before wake | resumes (owner report) |
| `pm_test=freezer`, 30 s | unplug | passes, resumes on battery |
| `pm_test=devices`, 30 s | stay connected / unplug | passes / resets |
| `pm_test=devices`, `pm_async=0` | stay connected / unplug | passes / resets |
| `pm_test=devices`, charging port `1-0033` unbound | stay connected / unplug | both pass |
| Real s2idle, charging port `1-0033` unbound | stay connected / unplug | both pass |

The PM tests and final real-sleep tests write `mem` directly to
`/sys/power/state`, bypassing systemd sleep hooks. The unbind scripts first
negotiate charging normally, unbind only the charging port, wait 10 s and
check that the separate EC driver still reports AC online and Charging.
The other USB-C port stays bound. The driver is rebound after each successful
test. No automatic sleep workaround is installed.

Real-sleep control: 22:40:25 to 22:41:37. Unplug: 22:42:10 to 22:44:34.
Both logs show `pm_test=none`, `suspend-to-idle`, wake from IRQ 225
(`pmic_pwrkey`), successful resume and rebind. The unplug run's immediate EC
snapshot still said Charging and resume logged an EC read error `-13`;
later checks showed AC and USB-C offline and battery Discharging. An EC
read error therefore does not by itself explain the reset.

This supersedes the earlier inference that absent journal/pstore records
locate the reset below Linux. Lid movement, actual s2idle entry and parallel
PM callbacks are not required for the device-test failure. Reset timing is
uncertain: the delay observed by the owner cannot establish whether the
initial fault happens at unplug or during resume.

**Strong suspect: `samsung-emuec` activity or the USB state it establishes.**
Unbinding removes its IRQ handler and cancels work, but also calls
`samsung_emuec_detach()` while hardware is awake. That changes USB role,
orientation, retimer and mux and unregisters the partner. The tests do not
separate those effects or identify a faulty function. The real-sleep result
is one successful unplug run; lid-driven systemd suspend and other ports or
peripherals remain to be checked with any eventual workaround.

Next: separate event quiescing from pre-suspend USB detach with a targeted
`samsung-emuec` module experiment. A full kernel rebuild for persistent
console logging is deferred. See the [Fedora handoff](handoff-fedora-suspend.md)
for the build baseline, proposed experiment and test sequence.

### Reproducing the isolation tests

The tested scripts are now under `tools/power/`. These are interactive
hardware diagnostics, not an installed fix: save work first because the
failing variants can reset the machine. Use the built-in display, keep the
lid open, and connect the charger before each run. Avoid docks or external
displays for the unbind experiments, which temporarily detach that port's
USB role and mux as well as its driver.

| script | difference from the baseline |
|---|---|
| [pm-freezer-test.sh](../tools/power/pm-freezer-test.sh) | freezes processes, leaves devices operational |
| [pm-devices-test.sh](../tools/power/pm-devices-test.sh) | suspends devices, pauses 30 s, resumes automatically |
| [pm-devices-serial-test.sh](../tools/power/pm-devices-serial-test.sh) | devices test with `pm_async=0` |
| [pm-devices-no-pdic-test.sh](../tools/power/pm-devices-no-pdic-test.sh) | devices test with charging-port driver unbound |
| [s2idle-no-pdic-test.sh](../tools/power/s2idle-no-pdic-test.sh) | real sleep with charging-port driver unbound |

Each accepts `control` (leave charger connected) or `unplug`. For example,
from the repository root:

```sh
sudo bash tools/power/s2idle-no-pdic-test.sh control
# Only after the control returns normally:
sudo bash tools/power/s2idle-no-pdic-test.sh unplug
```

Follow the script's timing instructions. The `pm-*` tests return
automatically; the real-sleep test requires a brief power-button press to
wake. If a control fails, stop before the unplug run. Scripts check s2idle
and the initial charging state, record before/after state, and restore
changed PM settings and driver bindings on normal return or a handled
error. A reset bypasses cleanup; a normal reboot binds the driver again.
They call the kernel directly and do not run systemd sleep/lock hooks.

Logs are written beside the scripts and ignored by Git; inspect/redact
kernel logs before sharing because they can contain network identifiers.
The original local captures from this investigation remain in
`~/book4-power-tests/`. Scripts were exercised on the hardware as recorded
above; no permanent sleep configuration or kernel/module change was made.

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

### 0004 on Fedora (4 October): event quiescing only, driver bound

[patches-experimental/0004](../drivers/anatase/patches-experimental/0004-samsung-emuec-quiesce-events-across-sleep.patch)
(PM notifier: interrupt masked and sync/HPD work stopped from
`PM_SUSPEND_PREPARE` to `PM_POST_SUSPEND`, no detach, one resync after),
Fedora `7.2.7-book4`, original `samsung-galaxybook-ec`, charging port
`1-0033`, `pm-devices-test.sh`:

| Test | Result |
|---|---|
| `pm_test=devices`, control | success |
| `pm_test=devices`, unplug | **success**, resumed on battery (AC 0, Discharging), no delayed reset |

Both ports logged `pm: quiesced` / `pm: resumed, resync`. The same test
reset the machine with the stock driver on Arch. So stopping the driver's
event handling across sleep is sufficient in this mode; the detach that the
unbind experiment also did is not needed. Next: real s2idle with the driver
bound ([tools/power/s2idle-bound-test.sh](../tools/power/s2idle-bound-test.sh),
control then unplug, power-button wake, 90 s watch).

| Real s2idle, driver bound, 0004 | Result |
|---|---|
| control (charger connected) | success, 90 s watch clean |
| **unplug during sleep** (asleep 13:52:45-13:55:12, wake by `pmic_pwrkey`) | **success**: resumed on battery, no reset in the 90 s watch, AC 0 / Discharging |

**First real-sleep unplug survived with the driver bound and in normal
operation.** Fix candidate: 0004. Still to do before calling it a fix:
ordinary lid-close suspend through systemd/KDE, repeated cycles, the other
USB-C port, charger plug-in during sleep (0004 does not wake for it; the
port should be negotiated on resume), USB data and DisplayPort after resume,
then the same on Arch.

Everyday checks with 0004 (Fedora, KDE, 4 October):

| Check | Result |
|---|---|
| Lid-close suspend via systemd/KDE, charger unplugged during sleep (14:02:40-14:05:08) | **success**, no reset |
| USB stick plugged in after that resume | enumerated first time (high-speed, `sdb`) |
| On battery, charger plugged in during sleep (14:07:20-14:09:46) | negotiated **20 V on resume, first attempt**, no `failed to clear interrupt`; charges from the lid opening (0004 does not wake for a plug-in) |

(One earlier first plug of the stick after the devices-mode tests failed to
enumerate, `Cannot enable`, and worked on replug; not reproduced after a
real sleep. The `book4-mods` hook logged GPIO 44 changes in these runs but
GPIO 44 was still reserved in the booted DTB, so it had no effect: 0004 alone.)

Other USB-C port (`3-0033`), lid-close unplug: **success** (14:12:07-14:14:30).

**Result: fixed by 0004**, now `drivers/anatase/patches/0002`. The reset needs
the charging driver's event handling to run across the sleep transition
while the power source changes; keeping it quiet from `PM_SUSPEND_PREPARE`
to `PM_POST_SUSPEND` avoids it. Exactly which call in that path brings the
machine down (an I2C access to the S2MM006, a typec/mux/role call, or the
EC side reacting to it) is not identified. Not yet tested: an external
display over USB-C after resume, many cycles over days, Arch.

### Wake for a charger plugged in during sleep (5 October, Fedora)

`patches/0003` (from `patches-experimental/0004`, written on Arch): while
quiesced, the interrupt of a port that was **empty** at suspend is armed as
a wake source; attached ports stay unarmed. Lid-close suspend via KDE:

| # | Setup / action during sleep | Result |
|---|---|---|
| 1 | battery, nothing, 11:30:50-11:41:05 | no spurious wake (both ports `wake=1`) |
| 2 | battery, plug in | woke 11:43:17, 20 V (request 1 -110, retried), KDE re-suspended 11:43:30; Charging on opening |
| 3 | charger, unplug | no wake, no reset; on battery after resume (EC status lags ~20 s) |
| 4 | battery, plug in then unplug | woke for the plug-in (20 V first try), slept again with the charger port `wake=0`; unplug left alone, no reset |

With 0001+0002+0003, a charger plugged in with the lid closed now charges
during sleep. Still to test: Arch/Hyprland re-suspending after the
charger wake (logind instead of KDE).

### CPU frequency scaling on Fedora (5 October)

Same as on Arch: no `cpufreq` until `scmi-cpufreq` was loaded
(`userspace/modules-load/book4-cpufreq.conf` in `/etc/modules-load.d/`).
Then three policies (`policy0/4/8`, 4 cores each), driver `scmi`, governor
`schedutil`, 710-3417 MHz. `openssl speed -seconds 3 sha256`, 16 KB blocks:
**2 435 106k** (about 850 000k without the driver). The fallback kernel
7.2.0-61 ships `scmi-cpufreq.ko.xz` too. `boost` is 0 (the X1E-80-100 can
boost one or two cores to about 4 GHz); left off, an option to try.
