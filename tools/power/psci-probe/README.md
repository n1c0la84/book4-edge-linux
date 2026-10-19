# EL2 DRIPS entry experiment

Question: when Linux at EL2 calls `CPU_SUSPEND(0x0200c354)` successfully,
how long does the firmware call take, and what visible interrupt/timer
state surrounds it?

Status: diagnostic code, **not yet built against the Book4 kernel or tested
on hardware**. Shell syntax and the offline report tests have been checked.
The development sandbox cannot access the prepared Fedora kernel tree or
use root. Run the build below before preparing the machine; a failed build
must be resolved before continuing.

## 1. Build on Arch

From this repository, as your normal user:

```sh
cd ~/Projects/book4-edge-linux
bash tools/power/psci-probe/build.sh
# Needed for the existing UFS workaround; rebuild if absent or kernel changed:
bash tools/power/icc-hold/build.sh
```

The default uses the same Fedora container and prepared `~/src/patchwork`
tree as the other diagnostic modules. It writes `psci_probe.ko` next to
the source, checks the kernel release, and does not load it. An alternative,
when a matching prepared tree is directly accessible:

```sh
bash tools/power/psci-probe/build.sh --local /path/to/prepared/kernel
```

Requires the running kernel's configuration, generated headers and
`Module.symvers`, plus `CONFIG_KPROBES`, `CONFIG_KRETPROBES`, module unloading
and debugfs. Do not force-load a mismatched module.

## 2. Fresh boot and preflight

Save work, then boot through the existing slbounce USB into **el2-drips**:
the hierarchical OSI DT with **`0x0200c354`**, without
`clk_ignore_unused`/`pd_ignore_unused`, and with `pcie_port_pm=force`.
Do not use `el2-dripspd` (`0x4200c354`) or `el2-pc`.
See [the EL2 boot instructions](../../../docs/el2.md#how-to-boot-it) if needed.

Use a fresh boot because earlier timer/GIC/regulator/SPSS experiments may
leave hardware state changed even after their modules are unloaded. Do not
run `tools/experiments/el2-probe.sh` or other tracing experiments concurrently.

```sh
sudo bash tools/power/psci-probe/run.sh check
sudo bash tools/power/psci-probe/run.sh prepare
```

`check` is read-only. It checks the actual boot log for EL2 and successful
OSI topology initialization, DT state/phandle linkage, SMC conduit, 12 online
CPUs, s2idle, and absence of the other experimental modules/dynamic probes.
It also requires the built probe artifact to match the running kernel,
before either preparation or a baseline can start. Baseline does not load it.
The early “failed to set PC mode” message is compatible with this experiment;
the later successful OSI initialization is required. This is not a new
firmware mode query or a mode-changing experiment.

`prepare` reproduces the existing test configuration:

1. Loads/verifies the **active-only UFS interconnect hold**, including that
   it actually acquired at least one path.
2. Forces the providers' `state_synced` attributes.
3. Unbinds Bluetooth and disables platform USB-controller wakeups.

These changes last for the boot. **Keep `icc_hold` loaded after testing**:
removing the UFS hold with boot floors released can break later suspend/resume.
Reboot restores the normal boot configuration. This does not install a sleep
hook or alter the default DT/boot entry.

## 3. Run four short suspends

Use the same charger connection, USB attachments, display configuration and
preparation for every run. Prefer battery, unplugged before the first run.
Keep the lid open so the hibernation-on-lid policy cannot replace this test.
Wake each suspend with the **power button after about 30 seconds**, timed on
a phone/watch. Wait for Wi-Fi/display activity to settle between runs.

```sh
sudo bash tools/power/psci-probe/run.sh baseline
sudo bash tools/power/psci-probe/run.sh timing
sudo bash tools/power/psci-probe/run.sh sampled
sudo bash tools/power/psci-probe/run.sh baseline
```

Each command requests one suspend, waits for completion, then saves results.
Run them individually. If a command reports a failed suspend or any peripheral
breaks, stop the sequence and retain that run's logs.

| Mode | Instrumentation |
|---|---|
| `baseline` | No new probe module; system-domain and hardware counter deltas |
| `timing` | Raw SMC return and hardware-counter timing, no GIC MMIO reads |
| `sampled` | Same timing, plus GIC/timer snapshots every 256th target call per CPU |

The second baseline helps detect changes across repeated suspends. Compare
the system-domain entry count over similar durations; an appreciable change
between timing and sampled runs indicates measurement interference.

The module refuses to load unless the kernel is actually running at EL2/VHE
on this Book4 model. It never acknowledges/clears/masks interrupts, modifies
timers, changes PSCI modes, or accesses display RSC registers. Like any new
kernel probe, it still needs hardware validation. If registration fails, save
the result directory and kernel log; do not remove its guards.

## 4. Results and interpretation

Each command prints its result directory under:

```text
~/src/book4-acpi/linux-state/psci-probe/
```

Directories are returned to the invoking user's ownership. They contain:

- `summary.txt`, `probe.txt` for instrumented runs, and runner exit status;
- before/after `aosd`, `cxsd`, `ddr`, system-domain counts and interrupt totals;
- clocks, interconnect summary when available, preparation state;
- running DTB/hash, kernel command line, boot ID, module list and source hashes;
- dmesg before/after and PSCI feature information;
- awake counter calibration and counter readings spanning the test.

`pm_wakeup_irq` may return “No data available” before the first suspend or
when no wake IRQ was recorded. This is saved as an unavailable diagnostic
with its error text; it does not abort the measurement. Required sleep
counters and suspend completion checks still fail the run on errors.

The module brackets **`__invoke_psci_fn_smc`**, not `CPU_PM_ENTER` or the
outer cpuidle entry. It filters function ID `0xc4000001`, state `0x0200c354`,
and the interval inside **`s2idle_loop`**, which starts after device noirq
suspend. It records raw PSCI codes: **0 success, -1 not supported, -3 denied**.
These differ from the Linux errno values in the older logs.

Timing uses the kernel's architectural-counter reader and `CNTFRQ_EL0`,
not frozen Linux trace timestamps. The awake calibration checks frequency and
progress. **Compare the reported s2idle-loop seconds with the external
stopwatch** before trusting suspend latencies: agreement between Linux clocks
alone is not independent validation. The report flags absent/unpaired calls,
missed probes, failed suspend, backwards/zero timing and missing samples.

Snapshots read non-acknowledging GIC pending/enabled registers, `ISR_EL1`,
`ICC_HPPIR1_EL1`, and control/status of CNTV/CNTP_EL02 and CNTHV/CNTHP_EL2.
Timer control bits are ENABLE=bit 0, IMASK=bit 1, ISTATUS=bit 2.
INTIDs 16–31 are PPIs; for INTIDs >=32, DT SPI number = INTID - 32.
HPPIR1 is a Group 1 view, not a view of all secure interrupts.

The report aggregates all sampled interrupts and keeps the last eight paired
snapshots per CPU (ring order, sort by `number` if needed). Samples include
the interrupted `pstate`; do not mistake handler interrupt masking for the
caller's masking. Pre/post snapshots are sequential reads, not atomic
hardware snapshots. Timing excludes the bulk of the register scans but
includes probe traps, wrapper instructions and return handling.

| Result | Next investigation |
|---|---|
| Pending/enabled IRQ at sampled entry, with short successful calls | Correlate that source, its timer status and its wake configuration |
| Short successful calls with no visible pending/enabled IRQ | PDC/secure wake signals and firmware coordination/handoff remain open |
| Long calls with hardware counters unchanged | Examine hardware resource votes and selected low-power state |
| Instrumented entry rate differs strongly from baseline | Reduce measurement overhead before drawing a causal conclusion |
| Hardware collapse counters advance | Preserve the full configuration and repeat before changing anything |

A zero PSCI return does not prove collapse. No visible GIC IRQ does not
exclude PDC/secure signals or an interrupt arriving after the snapshot.
`pm_wakeup_irq` is the final system wake source, not necessarily the cause
of every bounced firmware request.

Send the **four result directory paths**, their summaries, and your approximate
external sleep durations. No battery-drain conclusions should be drawn from
these 30-second tests.

Offline verification:

```sh
bash -n tools/power/psci-probe/{build,run}.sh
python3 tools/power/psci-probe/test_summarize.py
```

Implementation references:
[Linux kprobes](https://docs.kernel.org/trace/kprobes.html),
[Linux suspend ordering](https://github.com/torvalds/linux/blob/master/kernel/power/suspend.c),
[Linux PSCI SMC wrapper](https://github.com/torvalds/linux/blob/master/drivers/firmware/psci/psci.c).
