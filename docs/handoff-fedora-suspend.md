# Fedora handoff: charger-unplug suspend reset

Updated 4 October 2026. Resume here after switching from Arch to Fedora.
The diagnostic scripts and latest results were committed as `485d5de`.

## Objective and next action

Investigate the automatic reset after suspending on AC, unplugging the charger,
and resuming on battery. The next step is a **targeted `samsung-emuec` module
experiment**, not a full kernel rebuild. No new experimental patch has been
implemented yet, and no permanent workaround has been installed.

First inspect the Fedora kernel/build tree and establish which driver and DT
are actually installed. Then prepare a patch that keeps the charging port
bound and attached but quiesces its interrupt/work handling across suspend
and resume. This separates event handling from the USB detach performed by
our successful unbind experiment.

## What we established

Latest tests ran on Arch, `7.2.7-book4`, with the original `samsung-emuec`
plus the PD retry patch, **without driver suspend/resume callbacks** and
without the `book4-mods` GPIO44 sleep hook.

| Test | Charger action | Result |
|---|---|---|
| Real s2idle, lid open, power-button wake | Unplug while asleep | Automatic reset |
| Suspend, unplug, reconnect before wake | Wake on AC | Success (owner report) |
| `pm_test=freezer`, 30 s | Unplug | Success, returned on battery |
| `pm_test=devices`, 30 s | Stay connected / unplug | Success / reset |
| `pm_test=devices`, `pm_async=0` | Stay connected / unplug | Success / reset |
| `pm_test=devices`, only charging port unbound | Stay connected / unplug | Both succeed |
| Real s2idle, only charging port unbound | Stay connected / unplug | Both succeed |

The charging port was `1-0033`; `3-0033` stayed bound. Charging first
negotiated normally (20 V); after unbind, the scripts waited 10 seconds and
verified that the separate EC still reported AC online and Charging.
The driver was rebound after the successful tests.

The final real-sleep tests on 3 October were 22:40:25–22:41:37 CEST (control)
and 22:42:10–22:44:34 CEST (unplug). Logs show late/noirq suspend,
`suspend-to-idle`, wake IRQ 225 (`pmic_pwrkey`), successful resume and rebind.
Monotonic dmesg timestamps exclude the sleep interval; use the wall-clock
snapshots to assess sleep duration. The immediate unplug-run EC snapshot
still said Charging and logged an EC read error `-13`; later checks showed
AC/USB offline and battery Discharging. That error alone is not diagnostic
of the reset.

Interpretation:

- `samsung-emuec` activity **or the USB state it manages** is the strongest lead.
  Unbind removes the IRQ handler and cancels work, but also calls
  `samsung_emuec_detach()` while awake: USB role NONE, orientation NONE,
  retimer/mux SAFE, partner removal and cached attachment-state changes.
  We have not separated these effects or identified the faulty function.
- Lid movement, actual s2idle entry and parallel PM callbacks are not needed
  for the device-test failure. Other concurrency remains possible.
- `pm_test=devices` skips late/noirq and actual s2idle. An explanation relying
  only on the GENI controller's noirq sleep callbacks is insufficient.
- The roughly 30-second reset delay does not locate the initial fault at
  unplug versus resume. Empty journal/pstore records do not prove a firmware
  or hardware fault. The newer findings supersede that inference in older notes.
- Previous Fedora/Anatase and experimental-driver failures do not exonerate
  code common to those drivers. Windows reportedly survives the sequence.
- One successful real-sleep unplug run is evidence for isolation, not yet a
  validated everyday workaround. Battery-to-battery suspend also succeeded.

Earlier GPIO44 MODS testing changed the battery LED behavior but did not
prevent resets. A `timeout 1 gpioset` hook releases the line afterward;
retention cannot be assumed. Keep GPIO experiments separate from this test.

## Re-establish the Fedora baseline

From the Fedora checkout, inspect local changes before pulling:

```sh
cd ~/book4-edge-linux
git status --short --branch
# If clean:
git pull --ff-only
uname -r
cat /sys/power/mem_sleep
cat /sys/power/pm_test
cat /sys/power/pm_async
modinfo -n samsung-emuec
modinfo -F vermagic samsung-emuec
```

The recorded Fedora build tree is `~/src/patchwork`, previously branch
`book4/pd-retry` based on Anatase `anatase-7.2` (recorded base `2ad788424`).
**Reverify this; Fedora may retain earlier experimental changes.** Inspect:

```sh
git -C ~/src/patchwork status --short --branch
git -C ~/src/patchwork log -5 --oneline
ls -l ~/src/patchwork/.config ~/src/patchwork/Module.symvers
make -s -C ~/src/patchwork LOCALVERSION= kernelrelease
rg -n 'suspend|resume|dev_pm_ops|pm_notifier|samsung_emuec_remove|samsung_emuec_detach' \
  ~/src/patchwork/drivers/usb/typec/samsung-emuec.c
```

Match the configured tree, installed target kernel and module ABI before
building. `modinfo` describes the file on disk; it does not prove that the
running kernel loaded that same revision from its initramfs. Inspect source,
boot artifacts and logs, and reboot into a known baseline when necessary.
Check for `/usr/lib/systemd/system-sleep/book4-mods`, earlier experimental DTs
and patches `0002`, `0002-v2`, or `0003`. The direct-kernel test scripts bypass
systemd sleep hooks, whereas ordinary lid suspend does not.

At the end of the Arch session, settings were `pm_test=none`, `pm_async=1`,
`pm_debug_messages=0`, `pm_test_delay=5`, with the charging driver bound.
Do not assume these describe the Fedora boot.

## Design the next experiment

Review [the driver](../drivers/anatase/samsung-emuec.c), especially
`samsung_emuec_irq_thread()`, its delayed sync worker,
`samsung_emuec_detach()` and `samsung_emuec_remove()`.

Keep USB role, orientation, partner, retimer and mux state intact before
sleep. Mask/drain interrupt and worker activity before device suspension,
then reconcile hardware state only after the relevant devices have resumed.
A PM notifier using suspend preparation/post-suspend is a candidate to review,
not a completed design. Account for suspend abort, remove, repeated cycles,
HPD work, work rescheduling and pending interrupts. Avoid waiting for IRQ/work
while holding a lock those paths need. Verify that events cannot run before
the deferred resynchronization is safe.

The old `0002-v2` experimental patch already failed the real unplug case.
It reenables/resynchronizes in the driver's own resume callback; that does
not by itself guarantee that unrelated USB role/mux providers have resumed.
Do not simply repeat it and treat it as the new isolation experiment.

If quiescing alone succeeds, event timing/handling becomes the leading
explanation. If it fails while unbind still succeeds, isolate the pre-sleep
USB role/orientation/retimer/mux changes next. Neither outcome alone proves
a particular faulty function.

Do not substitute a sysfs USB-role `none` write for the detach comparison:
upstream DWC3 maps NONE to its default hardware mode, and that write does not
cover the orientation/mux operations. See the upstream
[DWC3 role implementation](https://github.com/torvalds/linux/blob/master/drivers/usb/dwc3/drd.c).
The exact installed DWC3 build has not been verified against that source.

## Build and installation boundaries

Keep the vendored original driver unchanged; store the new patch under
[patches-experimental](../drivers/anatase/patches-experimental/), following
the repository convention. Preserve existing build-tree changes.

[update-emuec-module.sh](../install/update-emuec-module.sh) demonstrates the
single-module external build: copy the desired `samsung-emuec.c` into a
temporary directory with `obj-m := samsung-emuec.o`, then build using
`make LOCALVERSION= M=... modules` against the configured original tree.
Generated headers and matching symbol versions must be present; do not
assume `modules_prepare` alone replaces a missing `Module.symvers`.
Build and inspect the module/vermagic first, before installation.

**The update script also installs the module and rebuilds Fedora's initramfs.**
It automatically applies only `drivers/anatase/patches/*.patch`, not
experimental patches. Review the intended source first. Its `.prev` module
and initramfs backups are overwritten each run: preserve uniquely named,
known-good matching copies before repeated experiments. Reboot to load the
new module and verify the booted revision. Keep the other Fedora kernel
available for recovery; restore the matching module/initramfs and run depmod
for the target release if rolling back.

Test on Fedora before transferring to Arch. Later,
[install/arch/sync-kernel.sh](../install/arch/sync-kernel.sh) runs from Fedora
while Arch is not running; it replaces the target kernel's **entire module
directory** in Arch and rebuilds its initramfs. Inspect its paths and target
release before use.

A full kernel rebuild for ramoops console logging is deferred. Arch had
`ramoops.ko` and built-in pstore, but no evidence of built-in pstore console
support and no accessible kernel `.config`. Verify the Fedora config if
returning to that route; persistent console capture would also need suitable
reserved memory/DT setup.

## Test sequence and records

Use the [committed diagnostics](power.md#reproducing-the-isolation-tests).
Save work, keep the lid open and use the built-in display without docks or
external displays. These hardware tests can reset the machine.

1. Confirm Fedora's driver/config baseline; keep the successful unbind
   experiment as the reference comparison if behavior differs.
2. With the experimental module **bound**, run `pm-devices-test.sh control`,
   then `unplug` only if control passes. These pause 30 seconds and return
   automatically. Do not use the no-PDIC script to validate a bound-driver fix.
3. If successful, prepare a matching real-s2idle test with the driver bound:
   charger-connected control first, then sleep 60 seconds, unplug, wait
   another 60 seconds, and briefly press power to wake. The existing
   `s2idle-no-pdic-test.sh` deliberately unbinds and is only the reference test.
4. Observe after resume, including beyond the previously seen reset delay;
   allow EC status to settle and record final AC/USB/battery state.
5. Before declaring a fix, repeat cycles, both charging ports, ordinary
   systemd/lid suspend, charger plug-in during sleep and USB/DP behavior.

Record kernel release, source/patch revision, charging port, PM mode,
wall-clock times, control/unplug result, delayed reset and battery state.
Scripts write logs beside themselves under `tools/power/`; those logs are
ignored by git. Review logs before sharing because they may contain device
identifiers or network details.

Original Arch logs and scripts are in `~/book4-power-tests/` on the Arch home,
including `lid-open-20261003-214113/before.txt`. They are **not in git** and may
not be visible in Fedora's home. The committed scripts match the tested code
apart from explanatory comments. Full investigation history is in
[power.md](power.md); prioritize its latest isolation section over older
hypotheses.

## Prompt to resume the work

> Read docs/handoff-fedora-suspend.md and the latest isolation section of
> docs/power.md. We are now on Fedora. Inspect the actual kernel build tree,
> installed driver and previous experimental changes, then implement and
> build the proposed event-quiescing-only samsung-emuec experiment. Preserve
> known-good rollback artifacts and guide the control/unplug hardware tests.
