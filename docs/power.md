# Power: suspend drain

**Others have reached full DRIPS on X1E (found 19 October, late).**
github.com/justririll/x1e-sleep (ASUS Vivobook S15, X1E80100, jglathe 7.2 at
EL2 via slbounce, DSPs started by qebspil): `aosd`/`cxsd`/`ddr` for ~99.7 %
of sleep, ~0.25 W (Windows ~0.23 W), from ~4 W. And on linux-arm-msm,
"x1e80100: no AOSD/CXSD in suspend with APPS votes at zero" (Michael Burch,
Dell XPS 13 9345, 8 October; replies from Konrad Dybcio and Val Packett, who
reports aosd/cxsd since reproduced at nVHE EL2 and EL1). Their documented
blockers and candidate differences for the Book4:
- the firmware computes the APSS wake deadline from the **EL1 timers**: at
  EL2 their `el1tmr` writes the next deadline into `CNTP_CVAL_EL02` before
  power-down and clears the CNTV that UEFI leaves armed; on the Vivobook the
  expired CNTV made firmware abort system-level entry. On the Book4,
  `timer_check` already disarmed CNTV at EL2 without fixing the bounce, so
  the physical timer deadline and other blockers still need testing. At EL1,
  Burch found that `tick_freeze()` disarmed CNTV and APSS did not collapse
  unless it was armed; the Book4's EL1 request is likewise held without
  collapse, but its cause is not yet established;
- **GPU RSC stale votes**: inverted `GMU_STATUS_FW_START` check in
  `a6xx_rpmh_stop()` (upstream "drm/msm/a6xx: Fix stale rpmh votes after
  suspend", d9108bfdb746, in 7.3), "the first big sleep blocker" there;
  Anatase 7.2.7 already carries both halves of it, so not a Book4 blocker;
- **LPASS tx/rx macro** clock votes kept by the ADSP forever (fixed in 7.3,
  b9b23e72ab, b05482e7ce);
- **qcom-geni serial** keeps the BT UART's clocks/CX votes (7.3, d0cd9c8d0fd5);
- QCE's DDR vote, a syscon TCSR clock pinning XO, and `regulator-always-on`
  panel supplies (Vivobook: 1.43 W -> 0.25 W). The Book4 DT has
  `VREG_OCTA_VDD`, `VREG_DISPLAY_VDD` and `VREG_EDP_3P3` always on;
- DRIPS must be system-suspend-only (runtime DRIPS hangs the SoC after the
  first s2idle); full AOSD resets about hourly there (CXSD-only workaround);
  a DC ZVA erratum with CL5 can hard-reset (maybe our 14 October reset).
The GPU RSC is separate from the display RSC found empty below. These fixes
were demonstrated on other boards; the Book4 has tested the PDC series but
not this timer/deadline and vote-fix combination. Their code is cloned at
`~/src/ext/x1e-sleep`.

**Combined test kernel `7.2.7-book4s` (19 October; `tools/kernel/build-sleep-kernel.sh`,
GRUB `test: sleep`, EL1):** branch `book4/7.2-sleep` = book4/7.2 + the PDC
series and domain_ss3 + upstream 7.3 LPASS tx/rx macro PM-clock series
(b9b23e72abef, b05482e7ce1b, b8ca90fafe6a) + upstream qcom-geni force
suspend (d0cd9c8d0fd5) + x1e-sleep's system-sleep-only genpd state, SS1 for
runtime idle and syscon fix + our DT change dropping `regulator-always-on`
from the panel chain (OCTA_VDD -> DISPLAY_VDD -> EDP_3P3). Modules
(`tools/power/sleep-modules`, under extra/): `cntv_arm` (ours: at EL1, arm
CNTV with a far, masked deadline at each CPU_PM entry where the frozen tick
left it off), `qcom_adsp_pwr_lmts` and `aoss_cxsd_only` (x1e-sleep,
unchanged; the latter not loaded by default). Its own release, modules and
initramfs, so the normal kernel is untouched. Test: `~/sleep-test.sh`.
**EL1 result (19 October):** all pieces active (PDC pass-through, SS1 +
system-sleep-only DRIPS, both modules loaded, ADSP channel bound; `cntv_arm`
armed CNTV at 24 CPU_PM entries). Two suspends: system domain entered once
and held, `aosd`/`cxsd`/`ddr` 0. Same as Burch's XPS 13 at EL1. The proven
configuration is EL2 with `el1tmr` (the real next deadline in the EL1
physical timer), never tried here: `tools/kernel/build-sleep-modules.sh`
adds it, entry `el2-sleep` (`~/el2-sleep-prep.sh`, `~/el2-sleep-test.sh`).

**Upstream's x1e PDC fix (found 19 October, evening; tested: not the blocker here, see below).** Linux 7.3
contains Qualcomm's series "x1e80100: Enable PDC wake GPIOs and deepest idle
state" (Maulik Shah; lore `20260707-hamoa_pdc_v3-v4-0`): on Windows
firmware the X1E PDC runs in **secondary controller mode, latching GPIO
interrupts as levels that upstream Linux never cleared**. 7.3 switches the
PDC to pass-through through an SCM write where newer firmware allows it,
handles secondary mode otherwise, acknowledges PDC IRQs in pinctrl, reverts
the x1e "bypass PDC wakeup parent" workaround, and adds `domain_ss3`
(`0x0200c354`, our DRIPS value) to `power-domain-system`. Commits:
irqchip `ef631c422f2c 8766c87e9bb4 f1a5a0f4c0ea 83e089ef0d4e 60caa95aa14a
45af2d61edf6 ad01c2b2f291 d307a7e7d939`, pinctrl `f790ea0b699d 77fbc756d9cb`,
DT `c39df6b350ef 95f827ceb21e`. Our 7.2.7 has none of it (no
`qcom_pdc_gic_secondary_set_type`). A latched wake at the PDC would explain
the EL2 "accepted, returns after ~50 us" and the always-pending lines.
Nobody has published `cxsd` counts with it yet (tested on a CRD and a
Slim 7x for GPIO wake). **Backport (19 October):** the nine commits apply
cleanly to `book4/7.2` (branch `book4/7.2-pdc` in our kernel fork, patch
files in `tools/kernel/pdc-backport/`, plus a local one-line log of the PDC
mode the firmware ends up in). `tools/kernel/build-pdc-kernel.sh` builds
only the image and the 14" DTB in a reflink copy of the tree (the drivers
are built in, the release stays `7.2.7-book4`) and adds GRUB test entry
`pdc`.
**EL1 result (19 October):** the firmware accepts the switch
(`qcom-pdc: x1e: pass-through mode (SCM pass-through write: 0)`), the DT's
`domain-sleep-0` is `0x0200c354`; one suspend: system domain entered once
and held, `aosd`/`cxsd`/`ddr` 0, as before. At EL1 the PDC latch was not the
visible blocker (Gunyah holds the request). Next: the same kernel at EL2,
where the PDC latch would explain the ~50 us bounces (entry `el2-pdc`).
**EL2 result (19 October, `el2-pdc`):** pass-through mode again, EL1 virtual
timer kept disarmed (`timer_check`: 0 re-armed in 1 310 536 exits). One
suspend: 1 288 849 accepted `0x0200c354` calls, `aosd`/`cxsd`/`ddr` 0. **The
PDC GPIO latch is not the blocker on this machine.** (Secondary mode only
latched GPIO interrupts; direct SPIs never were.) 7.3's x1e PDC/domain_ss3
work is right and worth having, but it does not bring CX collapse here on
its own.

**RPMh read-back (19 October, set up):** linux-next's `rpmh_read()`
(`edbafe65eef2`, Maulik Shah, "useful for clients … to know the settings
applied during bootloader stage", plus `e284de4dfc01`) added to the test
kernel (`pdc-backport/0011-0012`). `tools/power/rpmh-read` reads all 256
cmd-db addresses (ARC, BCM, VRM +0/+4/+8) through the APSS RSC, as booted and
after releasing the boot votes (`~/rpmh-read-test.sh`). It most likely
returns Linux's own DRV's setting, so it shows bootloader votes on our
channel that no Linux driver ever touched. **Result: loading the module
hung the whole machine** (EL1, `test: pdc`; nothing reached the journal after
the module build). Most likely the first read request never completes on
X1E (the read path was added for newer SoCs/RSCs), so the active TCS stays
busy and every RPMh client blocks. RPMh read-back is not available to us;
the script refuses to run.

**Current status (19 October 2026).** The SoC still never reaches deep sleep
in s2idle (`aosd`/`cxsd`/`ddr` stay 0 in every configuration tried). What
is established, in order of the sections below:

- Releasing the boot votes, `pcie_port_pm=force`, USB wakeup off and
  Bluetooth unbound bring every APSS (drv-2) RPMh vote Linux makes to 0 at
  sleep; best measured drain about 3.1 W (hour-long runs; differences of a
  few percent between runs are within the method's error). That is
  necessary, not sufficient.
- Windows' DRIPS is PSCI `0x0200C354`; our DT had no system-level idle
  state. With it, at EL1 under Gunyah the system domain is entered once per
  suspend and held, with no collapse.
- At EL2 (slbounce, no Gunyah) with the OSI hierarchy, TrustZone **accepts**
  `0x0200C354` (returns 0). Most calls return within about 27-107 us,
  roughly 16 000 times per second of suspend. The timed probe also put five
  calls in its 28-56 s histogram bucket and the sampled probe put three
  there; several CPUs appear to remain inside a successful PSCI call for
  nearly the whole suspend. The 19.2 MHz counter in `tools/power/psci-probe`
  measured 31-32 s in these requested ~30 s suspends, but no external
  stopwatch reading was recorded to validate suspend-time counter behavior.
  The overall mean call latency includes the long calls and is not typical.
  The variant with the StateType bit, `0x4200C354`, is `NOT_SUPPORTED`. A
  working PC-mode test was never achieved (the switch to PC failed), so
  PC vs OSI is still open.
- Interrupts: on the one CPU with a leftover EL1 virtual timer
  (`CNTV_CTL_EL02=5`, an EL2-boot artifact; KVM keeps PPI 27 enabled) PPI 27
  is pending and enabled at every call. But other CPUs bounce just as fast
  with no pending+enabled interrupt visible in the GIC right at the SMC
  (CPU 11: 65 983 calls, 0 of 257 samples). A pending+enabled GIC interrupt
  was not visible at those sampled boundaries; interrupts between snapshots,
  secure interrupts and PDC/AOSS-side wake or abort reasons remain possible.
- Things tried that did not change the result on their own: stopping the
  DSPs, stopping the Secure Processor (PAS 14), the PEP's `_DSM`/GPIO 44
  notifications, voting off the nine regulators Linux never votes, masking
  PPI 27. With several blockers, each could still be one of them.
- The display RSC (RPMh DRV 9), which UEFI leaves clocked and Linux never
  uses, holds no commands (read at EL2; at EL1 the read resets the
  machine). These Linux-side tests have not exposed the missing condition.

Windows' own DRIPS entry does no hardware setup (it only snapshots the sleep
stats), so whatever allows collapse is set up earlier. Next on Linux: compare
the Book4 with the working X1E configuration above, starting with the EL1
timer deadline and GPU RSC fix, then the remaining votes and supplies. The
[Windows investigation](windows-investigation.md) remains useful if those
tests do not explain the difference. Hibernation is a parallel workaround;
its entry currently resets before writing an image (end of this file).
The sections below keep the chronology; early hypotheses there are
superseded where this summary says otherwise.

**Latest reset investigation (3 October evening):** unbinding only the
charging port's `samsung-emuec` before sleep avoids the unplug reset in both
`pm_test=devices` and real s2idle. The tests implicate driver activity or the
USB state it manages, without identifying a faulty function. See
[the test matrix and reproduction scripts](#further-isolation-3-october-evening-charging-port-driver-unbind-succeeds).

**Drain investigation as of 14-15 October (superseded by the status
above):** two causes were identified then; the second ("the system domain
is never entered") was fixed by adding DRIPS to the DT. See
[Why the SoC never reaches deep sleep](#why-the-soc-never-reaches-deep-sleep-14-15-october-2026).

## Why the SoC never reaches deep sleep (14-15 October 2026)

Baseline, normal Arch boot (`clk_ignore_unused pd_ignore_unused`), lid
closed, 60 min on battery: **252 mAh = 3.76 W (7.0 %/h)**; `qcom_stats`
`aosd`/`cxsd`/`ddr` 0 before and after (`tools/power/sleep-drain.sh`). The
"1.7 W" in older notes was a miscalculation: 6-7 %/h of the 54.8 Wh pack is
3.3-3.8 W.

### 1. The firmware's boot votes are never released (ours, understood)

Interconnect, RPMh power-domain and clock-controller providers keep the
firmware's boot-time state (interconnect nodes at `INT_MAX`, i.e. DDR and
buses at maximum; CX/MX at boot level; boot-on GDSCs on) until their
`sync_state` runs, which needs every DT consumer bound to a driver. Here it
never runs (`state_synced` 0, `tools/power/power-dump.sh` lists them):

| Provider | Waits for | Why it never binds |
|---|---|---|
| `17500000.rsc:power-controller` (RPMh power domains) | `aaf0000` video clock controller | `CONFIG_SM_VIDEOCC_8550` not set (it drives `qcom,x1e80100-videocc`) |
| `interconnect-1` (mc-virt), `1700000.interconnect` (aggre2) | `crypto@1dfa000` | `CONFIG_CRYPTO_DEV_QCE` not set |
| GCC `100000`, GPU CC `3d90000` | `3d6a000.gmu` | the GPU driver uses the GMU without binding it |

In 7.2 the interconnect floors are dropped for all nodes at once, when the
last interconnect provider syncs (`icc_sync_state()`, one global flag). Both
modules build as `=m` with no change to the built-in kernel (vermagic
matches); `CRYPTO_DEV_QCE_*` bools only select algorithms inside `qcrypto`.

`clk_ignore_unused pd_ignore_unused` add to it: ~155 clocks are on in
hardware with no user (USB multiport and third USB controller at 200 MHz,
SD card, QUP serial engines, five unused PCIe controllers, UFS ICE at
403 MHz, camera PLLs). Without the flags 57 really switch off and everything
still works, but the boot console goes dark between `simpledrm` and `msm`
(no clocks/power domain in the `simple-framebuffer` node); the unused USB
GDSCs then still stay on until GCC syncs.

Windows' DSDT recipes (`tools/power/pep-dump.py` on the decompiled DSDT)
switch the same blocks off in D3, and keep UFS at 4.8 GB/s memory and
299 MB/s register bandwidth for the whole of D0.

### Forcing the sync breaks resume

`fw_devlink.sync_state=timeout deferred_probe_timeout=30` (the timeout is 0
in this kernel's config, so `fw_devlink.sync_state=timeout` alone never
fires), or per provider `printf 1 | sudo tee .../state_synced` (exactly
`1`, no newline), forces it. After that, `pm_test=devices`
(`tools/power/suspend-check.sh`) loses the disk:
`qcom-qmp-ufs-phy 1d80000.phy: phy initialization timed-out`,
`Failed to calibrate PHY: -110`; the suspend is aborted ("Some devices failed
to suspend") and every read/write fails afterwards. In one such run Wi-Fi
also failed to resume (`ath12k ... error -108`). Bisected:

- Syncing only the interconnects is enough to break it (the RPMh power
  domains and clock controllers were not tested on their own). Syncing
  mc-virt alone changes nothing, because the floors only drop when the last
  interconnect provider (aggre2) syncs.
- With `tools/power/icc-hold/icc_hold.ko` (holds a peak vote on any DT
  node's interconnect paths), holding **any one path** saves UFS: UFS's own
  `ufs-ddr` or `cpu-ufs`, the Wi-Fi PCIe controller's, or the display's
  memory-only or register-only path. So it is a bus/rail level (RPMh raises
  the CX/MX corner with any bus clock), not one path.
- `tools/power/icc-trace.sh`: on resume UFS re-votes only its PWM-gear levels
  (`ufs-ddr` 255 591 kB/s, `cpu-ufs` 1 000 kB/s peak) while the PHY is
  re-initialised, and raises them only once the link is back at HS gear.
  At probe the driver votes `MODE_MAX` first (`ufs_qcom_icc_init()`).
  `tools/power/ufs-qcom-max-bw-during-phy-init.patch` does the same in
  `ufs_qcom_power_up_sequence()`. With it and no held path, the cycle no
  longer aborts at UFS but the machine then stops with a black screen and
  logs nothing; untested further.
- An **active-only** hold (`tag=3`: applied while the CPUs run, dropped by
  RPMh in deep sleep) made a full real suspend and resume work with all
  providers forced to sync and no `clk/pd_ignore_unused`, stock modules:
  **3.53 W** for 61 min, counters still 0. Small gain, because of 2.

(`crypto@1dfa000`'s own vote was a wrong lead: with `qcrypto` loaded the
interconnects sync, CE0 is voted, and UFS still fails the same way.)

### 2. The system power domain is never entered in s2idle (upstream, open)

`/sys/kernel/debug/pm_genpd/power-domain-system/idle_states` after that
hour: state S0 used 31 833 times in normal idle, **S2idle 0**. The CPUs do
sleep (each entered `cpu-sleep-0` once for the whole hour, no spurious
wake-ups; `s2idle/time` stays tiny because timekeeping is frozen), but the
step that hands the SoC to RPMh for CX collapse never happens in s2idle.
Known on Snapdragon X: an IdeaPad Slim 5x owner
([linux_ms_dev_kit #94](https://github.com/jglathe/linux_ms_dev_kit/issues/94))
has the same counters; with the PDC wake-up series, Ulf Hansson's
cpuidle-psci/genpd fixes and a `domain_ss3` system idle state the system
domain does power off in s2idle, but `cxsd`/`aosd`/`ddr` stay 0, the drain
went up to ~3.6 W and the lid switch stopped working. Qualcomm's
["cpuidle/pmdomain: Correctly track state of excluded CPU clusters"](https://ratatoskr.run/linux-pm/2026/08/17394853/t)
(in linux-next since September) fixes one reason the system domain refuses
to power off. Nobody reports CX collapse on Linux yet; Windows Modern
Standby on these machines is quoted at 0.2-0.5 W.

**Status:** stopped here. Fixing 1 alone gains little until 2 is solved
upstream; when it is, 1 is needed: `CONFIG_SM_VIDEOCC_8550=m`, a driver (or
`status = "disabled"`) for `crypto@1dfa000`, the GMU blocker, and resume
votes for UFS (the patch above) and whatever stops after it. For nights on
battery: hibernation (TODO) or shut down.

### 3. Our DT has no system-level idle state; Windows' is DRIPS (16 October)

Ghidra on Qualcomm's PEP (`qcpep8380.sys` 10.9, from the Windows driver
store) and the DSDT: the PEP registers its system-collapse callbacks
(`PepIdleEnterSysCollapse`/`Exit`) on the LPI mode `platform.DRIPS`; they
only timestamp and collect subsystem sleep stats. The state itself comes
from `\_SB.SYSM._LPI`: SS1 (`0x100`), SS2 (`0x200`) and **DRIPS (`0xC300`,
wake latency 5 ms, min residency 9 ms)**, reachable only from cluster CL5
(`0x50`, enabled parent state 3) with cores in C4 (`0x4`). The PSCI
parameter Windows uses for DRIPS is therefore **`0x0200C354`**, the value of
the `domain_ss3` state tried in linux_ms_dev_kit #94.

In our running DT `psci/power-domain-system` has **no `domain-idle-states`**
(only the clusters have `0x01000044`/`0x01000054`), although the RSC and
all three clusters are its children. So Linux never requests a system-level
PSCI state, which is when the RSC writes the RPMh sleep sets.
`tools/power/drips-dtb.sh IN OUT` adds DRIPS to a DTB
(`book4-drips.dtb` from `book4-default-1010.dtb`). Test: GRUB test entry
`drips`, then `tools/power/sleep-drain.sh drips` for an hour (the
`system-pd-s2idle` sum now includes the new state).

**Result (16 October, `drips`, with `clk/pd_ignore_unused`, boot votes
held):** the system domain entered DRIPS for the first time
(`system-pd-s2idle` 0 -> 1: once, for the whole hour), `aosd`/`cxsd`/`ddr`
still 0, and **4.67 W** (baseline 3.76 W). So the request now reaches RPMh,
which refuses to collapse because sleep-set votes remain (boot floors,
~155 unused clocks). Next: DRIPS with the votes released (no flags, every
provider forced to sync, active-only UFS hold as on 15 October).

**Result (16 October, `drips-synced`: no flags, all providers synced,
active-only UFS hold):** resume fine, DRIPS entered again (also 12 338 times
in runtime idle), `aosd`/`cxsd`/`ddr` still 0, 3.91 W over only 18 min.
`adsp`/`cdsp` sleep ~97 % of the time, so they are not the blocker.
`bi_tcxo` (RPMh XO, the non-`_ao` one that also votes in the sleep set) has
10 users awake: Wi-Fi's PCIe PHY (`tcsr_pcie_2l_4_clkref_en`,
`pcie4_pipe_clk`), the USB PHYs, UFS PHY, eDP PHY. Any one held over
suspend prevents XO shutdown (`aosd`). The Windows PEP has a "PCIe HW DRV"
(`PcieHwDrv`, `RSC_DRV_PCIE`, `gcc_pcie_rscc_*`) that takes PCIe's votes
off the APSS so the SoC can collapse with the link in L1ss; Linux does not
use the PCIe RSC (those clocks are off). Next: `drips-nowifi`
(`pci@1c08000` and `phy@1c0e000` disabled, USB wakeups off).

**Taking the Wi-Fi link down for suspend (16 October, evening).** PCI
remove of the card alone leaves the link up (and ASPM off), so the host
driver keeps its resources in `suspend_noirq`. Adding Link Disable on the
root port (`setpci -s 0004:00:00.0 CAP_EXP+10.w=0010:0010`) drops the link
(`pciehp: Slot(0): Link Down`, `DLActive-`), and in suspend the controller
powers down (on resume `qcom-pcie ... PCIe Gen.3 x2 link up` from a fresh
host init). But the card does not come back: awake, clearing Link Disable
does not retrain it, and pciehp has turned slot 0 off and refuses to power
it on (`No such device`); after the suspend the link retrained but the
rescan found nothing. Wi-Fi needs a reboot each time. Cleaner route: make
`qcom_pcie_suspend_noirq()` deinit the host also when no endpoint driver
is bound, so a sleep hook only removes the card and rescans (which works).

**PHY review (16 October, book4/7.2 source).** In system suspend: UFS
(`spm_lvl 5`, link off) powers its PHY and ref clock down in
`ufs_qcom_setup_clocks()`; eDP's PHY exits in `msm_dp_pm_runtime_suspend()`.
USB keeps every PHY initialised (combo and eUSB2 ref clocks, so the XO vote)
whenever the controller may wake (`dwc3_suspend_common()`, host role,
`device_may_wakeup`): the default `power/wakeup` is `enabled` on all three.
PCIe: 7.2's `dw_pcie_suspend_noirq()` already sends PME_Turn_Off, takes the
link to L2 and deinits the host, but only if every device on the bus,
including the root port, is in D3hot (`pci_host_common_d3cold_possible()`).
No suspend today re-inited the controller, so it is not taken; the root port
needs `bridge_d3` to be put in D3hot. Test: `pcie_port_pm=force` (GRUB entry
`drips-pcie`), short suspend, look for a fresh `link up` after resume.
**It works:** with `pcie_port_pm=force` the suspend logs `Timeout waiting for
L2 entry! LTSSM: 0x11` (non-fatal), and on resume `PCIe Gen.3 x2 link up`
from a fresh host init; ath12k reloads its firmware and Wi-Fi reconnects
after 11 s, with no remove/rescan. Next: one hour with everything
(`drips-full`: DRIPS, no flags, providers synced, active-only UFS hold,
`pcie_port_pm=force`, USB wakeups off).
**Result (16 October, `drips-full`, 62 min): 3.06 W** (best so far:
baseline 3.76 W, hold-active 3.53 W), Wi-Fi back after resume, but
`aosd`/`cxsd`/`ddr` still 0 and the system domain entered once. With every
known XO/CX holder released the SoC still does not collapse: the remaining
blocker is unidentified.

**Suspect (16 October): UFS leaks enables on its `ref_clk`.** In the dump,
`clk8` (an RPMh XO buffer, voting in the sleep set too) has enable count 42,
all from `1d84000.ufshc` `ref_clk`. `ufs_qcom_enable_lane_clks()` enables the
whole clock bulk (`devm_clk_bulk_get_all()`, `ref_clk` included) without
checking `is_lane_clks_enabled`, while `ufs_qcom_disable_lane_clks()` is
guarded. It is called from `ufs_qcom_hce_enable_notify()`,
`ufs_qcom_resume()` and the ungate path of `ufs_qcom_setup_clocks()` (link
in hibern8), so overlapping calls leave references that are never dropped
and `clk8` can never be released for sleep. Same code in mainline.
Check: `~/ufs-refclk-check.sh` (count before/after two suspends); fix:
return early in `ufs_qcom_enable_lane_clks()` when already enabled.
**Confirmed:** `clk8` count 106 -> 106 -> 110 over two suspends, a few hours
into the boot (42 after 20 minutes). Fix:
`tools/power/ufs-qcom-lane-clks-guard.patch`, built with
`build-ufs-patch.sh PATCH`.
**With the fix (`ufsfix` entry, `drips-full`, 61 min): 3.11 W**, counters
still 0. `clk8` stays at 0 across suspends with the patch, so the leak is
real but was not what blocks XO shutdown (the earlier runs were on fresh
boots, where the leaked count was still low). The deep-sleep blocker
remains unidentified.
**Already fixed upstream (found 19 October):** Qualcomm's
`f07317a8d57f` ("scsi: ufs: ufs-qcom: Enable only lane clocks in lane clock
APIs", Nitin Rawat, reviewed by Manivannan Sadhasivam), queued in
`7.4/scsi-staging`, restores the guard and limits the lane-clock APIs to
the three lane clocks; its message names the same effect (blocked CXO
shutdown). No `Fixes:`/`Cc: stable`, so 7.3 doesn't get it automatically:
after 7.4-rc1, a stable backport request (or a cherry-pick in the Anatase
kernel) is the useful step. Our `tools/power/upstream/0001-*.patch` is
superseded and not sent.

**USB GDSCs (16 October).** The ten USB GDSCs are `PWRSTS_RET_ON` on X1E,
so `gdsc_disable()` leaves them on; Windows' PEP lists exactly these ten
as `SUPPRESSIBLE_RESOURCES` footswitches (INF blob `CSRL`).
`tools/power/gdsc-drips` collapses them at the start of noirq suspend and
restores them at the end of noirq resume. Result (`drips-full-gdsc`,
23 min): all ten collapsed and restored, **4.03 W, counters still 0**, and
on resume the runtime-suspended USB 2.0 controller (`a200000`, fingerprint
reader) died (`xHCI host controller not responding, assume dead`: it relies
on retention), plus `geni_i2c ... error turning SE resources:-13` on
b94000/b80000. Not the blocker; dropped.

**RPMh trace from boot (16 October, `trace_event=rpmh:rpmh_send_msg` plus a
`stacktrace` trigger).** In s2idle Linux does vote CX/MMCX/MX to 0
(`genpd_suspend_noirq` -> `rpmhpd_power_off`) and the buses to 0 in the sleep
set; journald's timestamps had suggested otherwise (they are read times).
But `xo.lvl` is voted on (3) from 9 s after boot and never changes, so the XO
can never shut down (`aosd` 0). Clock tracing (`clk_prepare`/`clk_enable`
transitions from a `clk_summary` baseline) at the moment CX is voted off: the
only clock still prepared below `bi_tcxo` is
`bi-tcxo-div2-clk` -> `gcc_gpll0` -> `gcc_qupv3_wrap1_s6_clk`, consumer
`a98000.serial`, the Bluetooth UART (`hci_uart_qca` keeps the port open).
Test: `~/bt-unbind-test.sh` (unbind `serial0-0`, suspend, compare counters).

**Clean run (fresh boot, providers synced, Bluetooth unbound):** at the
moment of sleep no clock below `bi_tcxo` is prepared, and every APSS RPMh vote
is off: `cx.lvl`, `mx.lvl`, `mmcx.lvl`, `xo.lvl` 0 (active, not overridden),
every BCM 0 in the sleep set or already 0. `aosd`/`cxsd`/`ddr` still 0. So
the remaining blocker is not a Linux (APSS DRV) vote: candidates are the
DSPs' own RPMh votes (adsp/cdsp DRVs, invisible to this trace) or the
hypervisor/firmware. (A runtime-PM experiment on the USB controllers leaked an
`SN4` vote through `dwc3_qcom_resume()` -> `icc_enable()` on that boot; not
present in the clean state.) Next: `~/dsp-stop-test.sh` (stop adsp and cdsp,
then suspend), then EL2.
**DSPs stopped (16 October):** adsp and cdsp `offline` (their own sleep
counters advance), providers synced, Bluetooth unbound: `aosd`/`cxsd`/`ddr`
still 0. Linux and the DSPs are both ruled out; next is the hypervisor: the
same test at EL2 (`install/el2/el2-dtb.sh /dtb-test/book4-drips.dtb
el2-drips -clk_ignore_unused -pd_ignore_unused`).

**The other RSC channels (16 October).** The apps RSC has `drv-0`, `drv-1`,
`drv-2` (DT `reg-names`); Linux is `drv-2` (`qcom,drv-id = <2>`), the others
are normally TrustZone and the hypervisor. A read-only `/dev/mem` dump of
their TCSes (`~/src/rsc-peek`) gets a bus error on both (`drv-2` itself is
refused by the strict-devmem check): their votes are invisible from EL1.

**Gunyah aggregates sleep requests across VMs.** In the public Gunyah source
(`hyp/vm/psci_osi/src/psci_osi.c`, `get_vpm_groups_aggregated_state()`) the
physical cluster/system level is the shallowest one any VM group allows; a
level any VM keeps at 0 stops the request there. The X1E platform code
(`platform_psci_*`) is not public, and Windows never runs Gunyah on these
machines, so this path is unlikely to have been validated on X1E. EL2 (no
Gunyah) is the test.

**AOP messages in qcpep8380.** `{class: lpm_mon, type: cxpc|rbsc, ...}` asks
the AOP to monitor CX power collapse; only sent when debug config 0x7b is
set. `{class: image, res: load_state|pwr_state}` reports subsystem images
(Linux's qcom_aoss sends load_state too). The rest are DDR/BCM/GPU tuning.
None looks like a missing "sleep allowed" message.

**EL2 (17 October), `test: el2-drips`** (no Gunyah, DRIPS DTB, no clk/pd
flags, providers synced, Bluetooth unbound, DSPs never start at EL2): a
2 min 20 s suspend, `aosd`/`cxsd`/`ddr` still 0, but `power-domain-system`
S2idle = **2 203 027** (at EL1: 1 per suspend). A 30 s suspend
(`~/irq-during-suspend.sh`): 965 760 system-domain entries against 58 178
`arch_timer` and ~14 000 IPIs (both including the awake seconds around it):
most DRIPS requests return from TrustZone immediately, without any interrupt.
So at EL1 Gunyah keeps the system-level request to itself (one entry,
held for the whole sleep, no collapse), and at EL2 TrustZone bounces it.
Boot log at EL2: `psci: [Firmware Bug]: failed to set PC mode: -3`
(DENIED), OSI mode in use. Open: a precondition Windows sets up (PDC, AOP
handshake), the composition/sequencing of the request in OSI mode, or DRIPS
being supported only under Hyper-V. All firmware-side; parked here.
Practical answer for nights on battery: hibernation (TODO).

**PEP's `LPDC` blob (17 October)** (INF `SystemLibResources`, `AeoB` format:
u16 type 0 int / 1 string / 3 package, u16 length; parser
`tools/power/aeob.py`): `INTERRUPT_CONFIG`, 27 entries
`[index, GSIV, 0, type 1|4, flags 0|8]` (`Acpi_PdcData.c`: `PdcIrq < 96`,
`LocalIrq > 0`). It is the DRIPS wake-source list: the three tsens "uplow"
interrupts (GSIV 538-540 = PDC 26-28 in Linux; PEP0 owns thermal) plus three
more tsens lines Linux's `pdc-ranges` do not cover (SPI 652-654), USB
controllers/PHYs (USB0/1/4), USB-C ports (PRT0-2) and the PMIC (PM01).
Not a precondition for DRIPS.

**How Windows defines "DRIPS reached".** The PEP's `NoHWDrips` bugcheck
(armed with `HWDripsTimeoutSeconds`) snapshots records 0 and 1 of the AOP
sleep-stats array (32-byte `{type, count, last_entered, last_exited,
accumulated}`, the layout `qcom_stats` reads) and fires if either count did
not advance: records 0/1 are `aosd` and `cxsd`, the counters used here.

**The PEP never executes DRIPS (17 October).** No PSCI call anywhere in
`qcpep8380.sys`: its only SMC is Qualcomm's secure-IO service (SCM
`0x2000501`/`0x2000502`, read/clear of a protected status register in one
interrupt handler). Imports: `PoFxRegisterPluginEx`, power-setting
callbacks, and only IRQL/timer functions from HAL. So the PEP provides policy
(platform states, vetoes such as "Required Bus BW vote veto", stats,
resource votes, the `CSRL` footswitches, the `LPDC` wake list); Windows'
kernel executes the `_LPI` states through HAL -> Hyper-V -> TrustZone.
Whatever makes TrustZone accept DRIPS under Windows but bounce it from Linux
at EL2 is therefore in Microsoft's HAL/Hyper-V path (or TrustZone only
accepting it from Hyper-V), not in Qualcomm's driver.

**Hypothesis (18 October): the request goes out as retention.**
`psci_cpu_suspend_enter()` only does a real power-down (`cpu_suspend()` with
a resume address) when `psci_power_state_loses_context(state)` sees the
StateType bit (bit 30 extended format, bit 16 original). `0x0200C354` (and
the DSDT's `0x4`/`0x50`/`0xC300`) has neither, so Linux calls CPU_SUSPEND
with entry point 0, as a retention state. A TrustZone that needs a resume
address for system collapse would refuse or no-op that, which matches the
millions of immediate returns at EL2. Test: the `el2-dripspd` entry
(`0x4200c354`). `~/el2-probe.sh` now also records histograms of the
`power_state` passed to and the value returned by `psci_cpu_suspend_enter()`
(kprobes).

**Modern Standby notifications go to the PEP too (18 October).** Besides
the EC (`LDOS`, `RESP`) and GPIO (44 `MODS`, 49 `HPDC`) writes, every phase
of PEP0's Modern Standby `_DSM` writes `{"MSBN", phase}` to
`\_SB.PEP0.FLD1`, a `GenericSerialBus` field on `\_SB.ABD` (`QCOM0427`,
`qcabd.sys`, "Qualcomm ACPI Bridge Device", channel 5), which forwards it to
`qcpep8380.sys`. The PEP stores the phase and, on `MS:MS+`/`MS:MS-`, pauses
or restarts one of its own timers, sends `in_standby = 1/0` to the ADSP over
GLINK (`APPS_ADSP_PWR_LMTS_GLINK_PORT`), and fires `ExNotifyCallback`
(`\Callback\QcDeepStandby`, Qualcomm's modem/WLAN "Deep Standby"). Nothing
reaches TrustZone, and the ADSP is already ruled out (stopped at EL1, absent
at EL2). Still to try on a DRIPS boot: GPIO 44/49 as the `_DSM` drives them
and the qseecom UEFI app unbound (`~/el2-probe.sh mods noqsee`).

**DRIPS with the power-down bit at EL1 (18 October, `drips-pd`,
`0x4200c354`):** PSCI returns 0 for all 95 requests (cores/clusters as
before: a few `-1` on cluster states, the OSI race), system domain entered
once, `aosd`/`cxsd`/`ddr` still 0. Under Gunyah the StateType bit changes
nothing; the EL2 run (`el2-dripspd`) is the one that tests it against
TrustZone. Note: the default DT reserves GPIOs `<35 1>, <44 4>`, so GPIO 44
(`MODS`) needs a DTB with `<35 1>, <45 3>` (`book4-drips-pd-gpio44.dtb`).

Kernel bug found on the way (18 October, 7.2.7): unbinding
`qcom_qseecom.uefisecapp.0` (`efivars: Unregistered efivars operations`)
with efivarfs still mounted, then suspending, oopses on resume in
`efivar_lock` (`efivarfs_unfreeze_fs` -> `efivar_entry_size`, from
`filesystems_thaw`): efivarfs resyncs without checking that the efivars
backend still exists. Unmounting efivarfs in the shell is not enough (services
keep it mounted in their own namespaces), so that test is dropped.

**TrustZone's answer at EL2 (19 October, `el2-dripspd`, `0x4200c354`):**
`psci_cpu_suspend_enter()` returns **-EOPNOTSUPP = `PSCI_RET_NOT_SUPPORTED`**
for the system-level request 622 493 times in one 30 s suspend (plus 16
-EPERM = `DENIED`); core and cluster states return 0 (clusters occasionally
`DENIED`, the OSI race). Under Gunyah (EL1) the same value returns 0 and
nothing collapses. The value passed Linux's extended-format check (bit 30
would be rejected otherwise), so TrustZone understands the format but does
not support a system-level power state with this StateID for the OS. Windows'
DRIPS therefore reaches TrustZone in some other form: Hyper-V composing a
different request, a different PSCI/SMC call, or a state TrustZone accepts
only from the hypervisor. Next: SS1/SS2 at EL2 (`el2-ss1`, `el2-ss2`) to see
whether any system-level StateID is supported.

**Hyper-V and Windows' kernel (19 October).** `hvaa64.exe` (no public
PDB) and `ntoskrnl.exe` (public PDB) contain the same Microsoft PSCI library
(`PsciLibraryInit`, `PscipInitDiscoverFeatures`, `PsciCpuSuspend`,
`PsciDecodeStateId`; Hyper-V's PSCI function table at `0xf800000066e0`).
- Windows: `HalpProcessorHaltPsciCpuSuspend(&power_state)` ->
  `PsciCpuSuspend(power_state, entry iff StateType bit, ctx)`, value
  unchanged, sent as HVC (`HalpPowerPsciHvcHandler`) under Hyper-V.
- Hyper-V: idle request type 5 -> `FUN_f8000022adc8` ->
  `FUN_f800002f6a68` = `CPU_SUSPEND(0xC4000001, power_state, ...)`, value
  unchanged (`FUN_f800002f6a40` only decodes the StateType bit). A core going
  offline uses `CPU_SUSPEND(0x10003)` or `CPU_DEFAULT_SUSPEND`.
- PSCI calls Hyper-V ever makes: CPU_ON/OFF/SUSPEND/DEFAULT_SUSPEND/FREEZE,
  SYSTEM_OFF/RESET/RESET2, MEM_PROTECT; **never SET_SUSPEND_MODE** (only
  probed with PSCI_FEATURES; OSI is treated as unavailable without it). In
  ntoskrnl `PsciSetSuspendMode` is reached only from
  `HaliSetSystemInformation` class 0x11 (no caller found yet).
So under Windows TrustZone most likely stays in its default
(platform-coordinated) mode, while Linux at EL2 switches it to OS-initiated
mode (`cpuidle-psci`). Hypothesis: Qualcomm's TrustZone supports DRIPS only
in PC mode, hence `NOT_SUPPORTED` under OSI. Test: an EL2 DTB without the
PSCI power-domain hierarchy, with core/cluster/DRIPS as flat CPU idle states
and the RSC flushing on the last CPU (cpu_pm) instead of the system domain.

**EL2, no PSCI hierarchy (19 October, `el2-pc`, flat states C4 / CL5
`0x01000054` / DRIPS `0x0200c354`):** TrustZone answers `DENIED` (-EPERM)
to DRIPS 900 411 times and to CL5 9 288 395 times (23 successes); C4 returns
0. So `0x0200C354` without the StateType bit is a state TrustZone knows (the
earlier `NOT_SUPPORTED` was for `0x4200C354`), and `DENIED` is OSI-style
coordination: TrustZone appears to stay in OS-initiated mode (it refused the
switch to PC at boot) and refuses cluster/system requests from a CPU that is
not the last in its domain. Next: OSI hierarchy + `0x0200c354` with the
return-value probe (`el2-drips`).

**EL2, OSI hierarchy, DRIPS `0x0200c354` (19 October, `el2-drips`): TrustZone
accepts DRIPS.** `CPU_SUSPEND(0x0200c354)` returns 0 for 690 627 calls in a
~30 s suspend (6 `DENIED`), cores and clusters as usual. The right request is
therefore Windows' value without the StateType bit, in OS-initiated mode.
The 690 602 system-domain entries against ~17 000 timer and ~12 000 IPI
interrupts suggest most calls return quickly, and `aosd`/`cxsd`/`ddr` stay 0.
The later PSCI probe measured the quick returns directly, alongside a few
calls that lasted nearly the whole suspend. Next at the time: measure each
call and inspect the wakeup IRQ (`el2-probe.sh lat`).

Timing at that stage used frozen s2idle timekeeping, so it could not measure
per-call latency there. The later `psci-probe` used the architected counter
instead. Awake with the display off, accepted DRIPS calls last 4-65 ms, but nothing collapses
while devices are active. CPU 0 had the EL1 virtual timer left enabled and
expired at EL2 (`CNTV_CTL_EL02=5`, `tools/power/timer-check`); disabling it
changed nothing. `tools/power/gic-pending` (GIC pending state at every
`CPU_PM_EXIT`) shows eleven SPIs pending at **every** return from deep idle
(572 158 of 572 158): the dp/dm HS-PHY wake lines of all four USB
controllers (PDC 11, 15, 49, 50, 58, 60, 61), `pcie4` msi0 (SPI 156), the
QUP SEs at `a98000` (SPI 806, Bluetooth UART) and `894000` (SPI 813), and SPI
352; PPI 27 (EL1 virtual timer) at 84 %. Linux never fired them. Next: are
they disabled-but-latched, and does clearing them (`gic-test.sh clear`) let
the collapse through?

Clearing pending-but-disabled interrupts before every entry removes six of
the USB lines (stale edges); SPI 352, 806, 813, 156 and 533 re-assert at once
(disabled in Linux, so a level held by the hardware). Entries still ~250 000.
Disarming CNTV/CNTP_EL02 at every CPU_PM entry/exit (they were never found
armed again) doesn't help either: PPI 27, enabled because KVM requests it as
the host vtimer, is still **pending and enabled at 77 % of CPU_PM entries**
(238 192 of 309 424) though Linux handled it once all boot. Next: disable
and clear PPI 27 at every entry (`gic-test.sh clear ppi27`).

With PPI 27 disabled it is gone, yet ~220 000 entries remain and at 97 % of
`CPU_PM_ENTER`s nothing enabled is pending. Still asserted (disabled in
Linux): SPI 806 (`a98000`, Bluetooth UART), SPI 813 (`894000`, the debug
UART), SPI 156 (`pcie4`, Wi-Fi), SPI 533 (`usb_1_ss2` dp HS-PHY) and **SPI 352
(INTID `0x180`), the Secure Processor `\_SB.SPSS` (`QCOM0C8D`)**, which Linux
has no driver for. The PEP's `_DSM` subsystem list (`SUBI`) is adsp, cdsp,
**spss**, and `qcsubsys_ext_spss8380.inf` sets
`SubsysUefiLoadedImageAction=1`: UEFI loads and starts SPSS (`RSPU.bin`) and
the Windows driver adopts it. Under Linux it would run, unattended, with
its interrupt raised, and never be put to sleep. Next: its SMEM sleep stats
(`tools/power/spss-check`, `~/spss-check.sh`).

SMEM has no per-subsystem sleep stats here (every host falls back to the
same global items 602-631, none of them sleep stats). TrustZone does manage
SPSS as PAS 14 (`qcom_scm_pas_supported(14)` = 1), and
`qcom_scm_pas_shutdown(14)` returns 0, but SPI 352 stays pending at every
exit and the bounces are unchanged (273 895 accepted DRIPS calls, counters
0). SPSS is not why TrustZone returns at once. Last check of the
pending-line idea: silence Bluetooth, the debug UART and Wi-Fi together
(`~/quiet-lines-test.sh`).

Unbinding Bluetooth and both UARTs and removing Wi-Fi doesn't deassert their
lines (unbinding doesn't reset the hardware's interrupt status), and the
bounces are unchanged (242 908). Since the GIC doesn't turn disabled
interrupts into wake requests, and the same lines are asserted at EL1 where
DRIPS is held, the EL2 bounce path ends here.

**Windows' DRIPS entry does no setup.** The PEP's `platform.DRIPS` callback
(`PepIdleEnterSysCollapse`, `FUN_140012ce0` -> `FUN_140020678`) only takes a
stable snapshot of the sleep-stats records for the `NoHWDrips` check. The
collapse depends on state set up earlier, at boot or as devices go to sleep.

**Regulators Linux never votes.** `rpmh-regulator` can't read state back, so
a regulator without a Linux consumer stays "unknown", `regulator_late_cleanup()`
skips it, and it keeps UEFI's last vote on the HLOS DRV. 18 are in that
state here. Nine of them are ones the PEP has off while their device sleeps
(`l1c l1d l1i l2c` and `l3d` in `GPU0`'s active recipe, `l3c` for USB3/PCI3
in D3, `l8b` for USB2 in D3, `l6b`/`l9b` for the SD slot). Test: vote them
off (`tools/power/vreg-off`, `~/vreg-off-test.sh`).

At EL1 (`drips-noflags`), with those nine voted off: DRIPS entered once and
held, counters 0. Not the blocker. Side effect: on resume the USB QMP combo
PHY `fda000` timed out (`phy initialization timed-out`), so one of them
(probably `l3c`, 0.912 V, "USB3" in the PEP) supplies it although the DT
has no such consumer.

**Other RPMh voters.** `Resources-VRDL` names three DRVs: `HLOS_DRV` 2
(Linux's), `DISPLAY_DRV` 9 (`/icb/arbiter/display`) and `PCIE_DRV` 16. Only
`\_SB.PCI6` (PCIe 6A, the M.2 slot; `_STA` needs `PRP6`, which is only set by a
hot-plug probe) uses `PCIE_DRV` in the recipes. `DISPLAY_DRV` is used by the
display driver itself: `qcdxkm8380.sys` has `MDSS_RSCC_REGS`,
`RsccSendVoting`, `RsccComputeAbVote`, `RsccSetVoltageVoteData`. Linux never
uses the display RSC, yet `disp_cc_mdss_rscc_ahb_clk` and
`disp_cc_mdss_rscc_vsync_clk` are on in hardware with enable count 0: UEFI
started the display RSC and left it running. Next: dump its registers
(`tools/power/rscc-dump`, `~/rscc-dump.sh`) for commands left by UEFI.

At EL1 the dump reset the machine on its first read (the previous boot's
journal ends right after the module build; nothing was logged). Under Gunyah
the display RSC isn't mapped for the Linux VM, so Linux can't read it or
vote through it there. A read is only possible at EL2 (where TrustZone's own
protection may still reset), and `rscc-dump.sh` now refuses EL1.

At EL2 (19 October, staged reads): stage 0, `0xAF20000 + 0x0` =
`0x00030000`, an RSC v3.0 ID word, so the address is right and readable
there. Stage 1 (first 0x100 bytes): solver config `0x01040401` (hardware
solver present), `0x80000002` (2 TCSs of 16 commands), and at `+0x20..+0x2C`
the PDC sequencer start/match values and slave ID 1, as in Qualcomm's
downstream display-RSC map (`qcom,tcs-offset = <0x1c00>`, one sleep and one
wake TCS). Stage 2 (a 20 KB sweep of both regions) reset the machine, so
`rscc_dump` now refuses it; stage 3 reads only the two TCSs (`0x1C00`,
stride 672) and names their command addresses from cmd-db.

Stage 3 (19 October, EL2): both TCSs idle (status `0x1`), no command
enabled (`enable 0x0000`), and every MSGID/address/data word is 0: UEFI never
programmed the display RSC, so it holds no vote. (A vote sent and then
wiped would still be in force at the AOSS; rpmh-rsc leaves address/data in
place after sending, so this is unlikely.) **Display RSC lead closed.**

#94 on 15 October (Slim 5x, x1p42100, jglathe 7.2.9-jg-0): s2idle 2.05 W,
`deep` (PSCI system suspend, resumes there) 1.89 W, `qcom_stats` still 0 in
both. Not directly comparable (8-core Purwa, different board). Jens'
`hamoa.dtsi` on `jg/ubuntu-qcom-x1e-7.2.y` has the same empty
`power-domain-system` (`/* TODO: system-wide idle states */`), so DRIPS has
not been tried there either.

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

**0004 does not fix it** (7 October, 15:18, Arch, 65 W charger, awake,
`charge-test.sh awake-0004 20`): clean negotiation (5 V at attach, 20 V /
3.25 A on the first request 3 s later), yet 80 -> 79 % in 22 minutes
(-36 mAh, about -1.6 W into the battery). Still open: the same 65 W charger
on the sleep path (it has never been seen charging this machine; it works
with other machines), or the 60 W charger awake, to rule the charger out.
If the awake path is confirmed: [handoff-windows-scdt.md](handoff-windows-scdt.md).

Battery trip point (Windows' only extra EC write at a plug-in, `_BTP` to
0x91-0x92), 8 October, 65 W, awake, 0004, `ectool.py btp-plugin` 15 s
after the plug-in: charge-test printed 95 -> 87 %, -11.4 W, but **that
result is invalid**: the "before" 95 % was stale (unchanged since an earlier
event), the reading jumped to 87 % at the plug-in itself (10:39:37) and
then did not move for the whole test, nor for 20 minutes on battery
afterwards (87 %, -79 mA, 17.12 V, constant). So the EC's battery block
seems to refresh **only at power events** (plug-in, unplug, maybe resume),
on battery as well as on AC, not just "freeze while a charger is
connected". The trip point test says nothing either way.

Cause found the same day: **the driver caches, not the EC.** `ectool.py
battery` read live values (rate 562 -> 460 mA, voltage 16623 -> 16616 mV
between two runs) while sysfs stayed at -122 mA / 16.75 V.
`samsung-galaxybook-ec` reads the EC battery block only at probe and from
its interrupt, which the EC raises for plug/unplug only. Fix:
[patches-galaxybook-ec/0001](../drivers/anatase/patches-galaxybook-ec/0001-samsung-galaxybook-ec-refresh-battery-on-read.patch)
(re-read when older than 1 s, like the ACPI battery driver), installed with
`install/update-galaxybook-ec-module.sh`. **All earlier charge-test results
are suspect**: their "before" value was whatever the last plug/unplug
event left, and "during" readings never moved. The awake-plug-in "stall"
(1-2 W) must be re-measured with the fix before anything else. Fix installed
on Fedora and Arch on 8 October: values now change between events.

First valid awake measurement (8 October 11:43, 65 W, Arch, 0004,
`charge-test.sh awake-fixed 24`, readings live): contract 20 V / 3.25 A
after 3 s, then battery current 14-66 mA for ~5 min and a steady
**~300 mA (~5 W)** after that; 78 -> 80 % in 24 min, **3 W average**. The
awake stall is real. Next: the same measurement for a plug-in during sleep
(lid closed, plug in, open after a minute) to compare the current.

Sleep attempt (12:10, `asleep-fixed`): the plug-in woke the machine
(patches/0003) and the contract (20 V / 2.99 A) was negotiated after
resume, so it was another awake plug-in: 79 -> 82 % in 21 min, ~200-300
mA, 5.2 W. Both valid runs were at **78-82 %**, where the charger may
already be tapering, and the earlier "sleep plug-in charges fine" came from
stale readings too. Decisive next test: awake plug-in **below ~50 %**
(`charge-test.sh awake-low 20`); ~20 W or more = nothing broken, ~5 W =
real problem.

Real sleep charge (12:34-13:50, lid closed, attached during sleep, live
readings since the fix): 82 % -> about 92 % in 76 min (back-calculated from
88 % after ~19 min awake at -540 mA), **~5 W, the same as awake** at this
level. So above ~80 % sleep and awake charge alike; the "awake stall" was
most likely stale readings plus the normal top-end taper. The below-50 %
awake test remains the confirmation. Both awake failures so far are with the 65 W charger;
next: the 60 W one awake without EC writes (`charge-test.sh awake-60w`).

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
Searched the Windows partition (read-only, 7 October): no driver in
`DriverStore`/`drivers` and nothing under `Program Files/Samsung` contains
`SCDT` or `\_SB.ECTC`, as text or as the ARM64 immediate pair for 'SCDT'.
There are **no SSDTs**: Fedora's `~/src/acpi` holds the complete dump
(APIC, BGRT, CSRT, DBG2, DSDT, FACP, FPDT, GTDT, IORT, MCFG, PPTT, TPM2,
XSDT), so no ACPI table calls `SCDT` either (the DSDT's `External`
declarations are disassembler artefacts), and neither do Samsung's Store
apps (`WindowsApps`). `SCDT`/`CableDetect` may well be unused on this model,
which would make fix B a false lead. To settle it: in Windows, watch the
firmware's debug output (`SCDT` logs `SCDT:<value>` through `ADBG`) while
plugging in a charger. `ADBG` goes to `\_SB.SAFI.PRNT`: the string is
written to region `ECM2` (0x9F) and signalled with `Notify (SAFI, 0x89)` to
Samsung's "Samsung Firmware Interface" driver (`SAM0701`), only if it has
registered (`AVBL`), so DebugView will not show it; the capture has to come
from that driver. Steps for a Windows session:
[handoff-windows-scdt.md](handoff-windows-scdt.md). Only worth it if 0004
does not fix charging.

**Fix B is dead: Windows never calls `SCDT`** (8 October, Windows, 65 W
charger). The SAM0701 driver is `SafiDrv.sys` (service `SafiDrv`, oem27.inf,
2.12.27.700); `EC2.sys` is service `EC2` on `SAM060B` (oem79.inf,
15.27.1.994). Contrary to the guess above, SafiDrv passes every firmware
message to `DbgPrintEx` as `ADBG: <text>`, so **DebugView (elevated,
"Capture Kernel" + verbose: `Dbgview /k /v /l <file>`) shows all firmware
debug output** (truncated to ~15 characters). An ETW trace of the nine
provider GUIDs found in SafiDrv/EC2/EmuEC/UcmEm plus
`Microsoft-Windows-Kernel-Acpi` ran alongside; it contains no `SCDT`
either. Raw captures: `C:\scdt\` (`dbgview1.log`, `dbgview2.log`,
`scdt1/2.etl`).

| plug-in | firmware messages around it | `SCDT` |
|---|---|---|
| awake, lid open (97 %) | `GDRO>0x2`, `GPRO<1`, `Unknown event`, `CSFI=0x7A`/`DSBB=0x7A` (with hex buffers starting `43 58 7a 00`), `_Q66`, `_STA B1EX=1`, `_BTP<S…`/`_BTP<T…`, `NTCA=0x42`, `NTCA=0x84` | never |
| lid closed, in Modern Standby (`MS:DisplayOff`, `MS:MS+`, `MS:LPS+` logged) | same set: `LPS-`/`MS-`, `GDRO`/`GPRO`, `_Q66`, `_BTP`, `CSFI`/`DSBB`, `NTCA=0x42`, back to `MS:MS+` | never |

What those messages are (DSDT decompiled in Windows with Intel's
`iasl-win-20260408`, line numbers in that `dsdt.dsl`):

- **`_BTP` is the only EC write at plug-in.** After every `_Q66`
  (`Notify (BATC, 0x80)`) Windows' battery driver re-reads `_BST` and calls
  `_BTP` (~1368): first with 0, then with a value just below/around the
  remaining capacity (`RCAP` 0xDA4 = 3492 mAh, trip points 3437/3473/3474/3510).
  `_BTP` byte-swaps the 16-bit value and writes it to **`\_SB.ECTC.BTPC`,
  EC RAM offset 0x91-0x92** (region `ECR`, space 0xA1, the same map as
  `B1ST` 0x84, `LDOS` 0x89; high byte at 0x91). Standard Windows battery
  behaviour (a capacity alarm for the next status change); Linux on device
  tree never writes it. Probably not a charge-current control, but it is
  the one EC write Windows makes there that Linux does not, and cheap to try
  after an awake plug-in (`tools/ec/`, `charge-test.sh`).
- **`CSFI` / `DSBB`**: `CSFI` (~59672) passes a buffer to `\_SB.SAFI.DSBB`,
  a mailbox to SafiDrv (`Notify (SAFI, 0x87)`, waits for the reply). The
  buffers are Samsung settings calls in the `samsung-galaxybook` format
  (`43 58` = 0x5843, `7a`, `82`, ...): `82 e9 91` (reads as "get battery
  charge-control threshold" in that driver's terms, reply 0 = no limit),
  `82 a6 39`, `82 a6 42`, `82 88 4c`. Samsung's software reading settings,
  nothing charge-related is set.
- **`NTCA`** (~58335): logs and `Notify (\_SB.SCAI, Arg0)`; a Samsung
  notification, not an EC access.
- **`GDRO` / `GPRO`** (~59293): only read the data/power role from `EMOP`
  (`DROL`/`PROL`, served by EmuEC); `GDRO>0x2` at plug-in, `0x0` on unplug.
- **`Unknown event`**: `EVTQ` (~57975) got an EC event number other than
  0x51-0x54, 0x60, 0x61, 0x66, 0x7c at the plug-in; the charger events
  `_Q51`/`_Q52` (which read `PSRC`) did **not** run.

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
  timer**. Decoded 8 October: `{02|03, T/60, T%60}` / `{04, 00}` on the raw
  target 0x62, T one byte, unit unknown
  ([ec-protocol.md](ec-protocol.md#wake-timer-raw-target-0x62-decoded-8-october-2026),
  test: [tools/ec/wake-timer.py](../tools/ec/wake-timer.py)). Not related to the unplug crash, but it is how this machine could
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
- [`tools/power/sleep-drain.sh`](../tools/power/sleep-drain.sh) does the
  same and also logs the deep-sleep evidence: `qcom_stats` counters and the
  system power domain's s2idle entries.

## What we know about the sleep state

- **Windows reaches full low power in sleep** (`powercfg /sleepstudy`,
  8 October, sessions of 7-8 October on AC): hardware low-power time is
  ~98 % of each sleep session (e.g. 18 765 s of 19 063 s; 5 452 s of
  5 557 s). So the SoC can power-collapse on this machine; the Linux drain
  is a software problem. Those sessions were on AC, so they give no drain
  rate yet: an hour of battery standby in Windows would.
- **The machine stays asleep.** With `pm_debug_messages` on, one suspend of
  five minutes showed a single wake-up, IRQ 131 = `gpio_keys` (the lid), when
  the lid was opened. No wake-up storm.
- `/sys/kernel/debug/qcom_stats` (`aosd`, `cxsd`, `ddr`) read 0 on both
  kernels, before and after suspend, even since boot. Explained on 14-15
  October: the PSCI system domain is never entered in s2idle and the boot
  votes are never released, see
  [Why the SoC never reaches deep sleep](#why-the-soc-never-reaches-deep-sleep-14-15-october-2026).
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
3. ~~Compare with other X1E machines' reports~~: done 15 October, the same
   on an IdeaPad Slim 5x; see the section at the top.

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

## Hibernation (the practical fix)

Until the SoC collapses in s2idle, a night of suspend empties the battery.
`install/arch/hibernate-setup.sh` adds a 16 GiB swap file in its own btrfs
subvolume (priority below zram) and a systemd sleep hook that stops the
ADSP/CDSP before hibernating and starts them after resume (their firmware
doesn't survive power-off). The EFI variable driver is built in, so systemd
stores the image location in `HibernateLocation` and Arch's initramfs
(mkinitcpio `systemd` hook) resumes from it, with no `resume=` on the shared
command line. The PMIC RTC has no wake alarm, so `suspend-then-hibernate` is
impossible; `install/arch/hibernate-lid.sh` hibernates on lid close on
battery, suspends on AC, and hibernates at critical battery. Never boot
Fedora while Arch is hibernated: both mount the same btrfs filesystem.

First try (19 October): the swap file and the `HibernateLocation` path work
(the next boot's initramfs looked for the image at the swap file's offset,
found none, cleared the variable). But the DSP stop ran from a
`system-sleep` hook, after systemd had frozen the user session: stopping the
ADSP removes the sound card, which waits for PipeWire to close it, and the
frozen PipeWire never does, so the machine hung before writing the image.
The DSPs are now stopped by `book4-dsp-hibernate.service`, ordered before
`systemd-hibernate.service` (before the freeze) and started again on resume
(`StopWhenUnneeded`).

Second try (19 October): the service stopped both DSPs, then
`PM: hibernation: hibernation entry`, then the machine reset before a usable
image was on disk (the next boot did not try to resume and `/swap/swapfile`
still had a plain swap signature). Next: `pm_test` stages (`freezer`,
`devices`, `platform`, `processors`, `core`, then `test_resume`) to find the
step that resets (`~/hibernate-pmtest.sh STAGE`).
