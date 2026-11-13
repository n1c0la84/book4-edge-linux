# Open points

How the machine runs today, what is in progress and the hard rules:
[STATE.md](STATE.md). This file is the full list of open points, roughly in
order of everyday usefulness within each section; what is done is listed at
the end.

**Now:**

- [ ] **Live ISO and reset installer** (29 October): boot-test
      `install/arch/live-iso.sh` (EL1 and EL2 entries), then
      `sudo book4-install` (plan only) from the live session. After a reset
      the kernel tools (`sync-kernel.sh`, `build-sleep-kernel.sh`,
      `sleep-setup.sh`, `test-entry.sh`) still expect Fedora's `/boot` and
      GRUB: give them a Fedora-less path (`/boot/book4` + `book4-grub.sh`).
      Later a public variant without tcblaunch.exe and firmware (extracted
      from the Windows partition at first boot).
- [ ] **Awake reset at EL2, 29 October ~13:55** (book4s, 21 h 55 min up, on
      battery at ~46 %, no charger change): PMIC RTC back at 2024-05-29, so
      the PMIC itself went down. LightCraft 0.15 (wgpu/Vulkan compute on the
      Adreno) had been open since 13:50; 22 October's awake reset also came
      minutes after a new GUI app. The journal lost the whole boot: the next
      boot found `system.journal` damaged, the rename failed (EBUSY) and the
      file was replaced. Since then `install/arch/crash-log.sh` (journald
      sync 10 s + a plain-text copy per boot in `/var/log/book4-live/`).
      Next: reproduce with LightCraft on battery, `dmesg -w` over SSH to a
      second machine, then the same on the charger.
      **Third one, 1 November ~12:43** (book4s, boot `e00a5e3f`, 1 h 45 min
      up, ~1 h after waking from a 24 h sleep, on battery at ~62 %): the
      owner saw the screen freeze, then the machine rebooted. PMIC RTC back
      at 2024-05-29 00:00 again, so again a full PMIC power-on. Nothing in
      the log: the journal stops at 12:42:08, the plain-text copy at 12:42:39
      (uptime 6322 s), with only the timers' routine lines and no kernel
      warning. Google Chrome had been open since ~12:20 (27 min, so a weaker
      link to a newly opened GPU app than on 29 October). The crash-log
      service worked: it kept 30 s more than the journal.
      **Best lead (1 November): the X1 DC ZVA erratum.** Same symptoms
      reported upstream ("hang and then reset", nothing logged, in use or
      idle): icecream95/x1e-crash (reproducer `crash.c`, DC ZVA after the
      cluster leaves CL5), Jens Glathe's RFC "hamoa: Drop cluster_cl5 idle
      state" (lore `20260604-dc_zva_mitigation-v1-1`, suggested by Marc
      Zyngier, band-aid), Ubuntu LP #2158523 (T14s, resets every few hours).
      Our running DT has CL5 (`0x01000054`) in every cluster domain. Next:
      run `crash.c` once on book4s (expect a reset; `sync` first); if it
      resets, try the fix that does not cost idle power, clearing
      `SCTLR_EL1_DZE` and emulating DC ZVA for EL0 (Zyngier's Oryon
      erratum), before dropping CL5. Check power.md's sleep numbers after.
      **Reproduced 1 November 13:10** (book4s, EL2, battery): `crash.c`
      (x1e-crash `bb344c4`, `gcc -O2`) reset the machine within seconds,
      the screen froze first, and the PMIC RTC came back at 2024-05-29: the
      same signature as the three awake resets. Cause confirmed as far as
      a reproducer can confirm it.
      **Fix written (1 November):** sleep-backport 0043 (fork
      `book4/7.2-sleep` 561807a80), x1e-sleep's version of Zyngier's Oryon
      erratum: DZE cleared, EL0 `DC ZVA` emulated, `clear_page`/`memset`/MTE
      never use it, CL5 kept. Not built yet. Test: build and install
      (`build-sleep-kernel.sh`), check `dmesg | grep 'Broken DC ZVA'`, then
      `crash.c` must finish all 10000 rounds; then a few days of normal
      use, and power.md's sleep numbers unchanged. 0044 (6810f4d6d) covers
      KVM guests: `HCR_EL2.TDZ` on every vCPU, so guests see DZP=1 and any
      DC ZVA left traps to an UNDEF. Test: in the sandbox VM, `crash.c`
      should die with SIGILL (host log: "Unsupported guest access") and the
      host survive. The test branch `book4/7.2-sleep-spk` lacks 0043/0044.
      **Built and booted (1 November):** book4s #5 (0043) printed "CPU
      features: detected: Broken DC ZVA", EL0 reads `DCZID_EL0=0x14`
      (DZP=1), and `crash.c` ran 9 min / ~1040 rounds without a reset (it
      reset within seconds before); stopped there for the reboot to #6
      (0043 + 0044, built incrementally). **Verified on #6:** `crash.c`
      ran all 10000 rounds (61 min, rc 0) on the host. In the Debian VM
      (guest kernel 6.12.113) `DCZID_EL0` reads DZP=1, `crash.c` dies at
      once with SIGILL, the host logs "kvm: Unsupported guest access" and
      stays up. Left: a few days of normal use without an awake reset, and
      power.md's sleep numbers re-measured (CL5 is kept, so no change
      expected); then close this item.
      **9 November:** birkskyum (omarchy#15860) says linux-omarchy carries
      Glathe's cluster_cl5 drop, so the hang can't happen there. Replied that
      SS1/DRIPS sit behind CL5 here (ACPI `_LPI` parent state 3; 0x0200C354),
      so the drop likely costs DRIPS s2idle, and **offered a measurement**:
      same kernel, DT with and without CL5, s2idle power and DRIPS entry
      counts. **He wants them** (9 November 20:20): our kernel in
      linux-omarchy's shape (no CL5, no system state; 7.3's hamoa.dtsi has
      no `system_pd` state at all) next to the current one. Ready (10
      November): `tools/power/el2-dt-test.sh omshape` (A) and `nocl5` (C:
      no CL5, SS1/DRIPS kept, tests our claim), dry-run on the live DT.
      Per variant (B = `el2-sleep`): after boot check the live DT and
      `/sys/kernel/debug/pm_genpd/*/idle_states`; `awake-test.sh baseline`;
      `sleep-drain.sh <variant>` (1 h+, battery) and one night; then a
      table in power.md and a reply with the numbers only (no holding
      reply). `el2-dt-test.sh <v> undo` after.
      **A (omshape), 10 November:** awake baseline 6.18 W (22 %, 17:35;
      B was 5.36 W on 23 October, not the same conditions: redo B). Sleep
      21:41-21:42, 61 min: 70 mAh = 1.20 W (±35 mAh EC step, so 0.6-1.8 W),
      `cxsd`/`ddr`/system-pd 0: no rail collapse, no DDR self-refresh.
      **Overnight 10-11 November (22:29-08:28, 600 min, battery, radios
      on): 867 mAh = 14.56 Wh = 1.46 W**, `cxsd`/`ddr` 0 % (sleep log; the
      script stopped on "suspend already in progress", the lid had started
      it). B has only one clean battery sleep of hours: 21 October, 249
      min, 0.90 W; most B nights were on the charger. Next: one B night on
      battery (normal entry, unplugged), B awake baseline, then C.
      **B awake, 11 November: 5.97 W** (A 6.18 W): CL5 is worth ~0.2 W awake.
      **Correction (11 November): linux-omarchy 7.3 is variant C, not A.**
      Mainline v7.3 `hamoa.dtsi` has `domain_ss3` (DRIPS, Maulik Shah's
      "Add deepest idle state") and CL5; omarchy-pkgs only drops CL5
      (`2151`, Glathe) and its Book4 Edge tree (`2592`) has no idle-state
      overrides. birkskyum's "no system-level idle state" is wrong, and so
      is our claim in the thread that the CL5 drop costs DRIPS: Omarchy's
      7.2.8 kernel with the CL5 drop and DRIPS reached 99.9 % CX/AOSS/DDR on
      a Surface Pro 11 (omarchy-pkgs#1315, ~0.25 W). C is the run that
      matters; correct both points when posting.
      **B sleep, 11-12 November (sleep log, battery, radios on):** 219 min
      0.70 W, 226 min 0.70 W, 73 min 0.74 W, `cxsd`/`ddr` 99.9-100 %.
      **C (nocl5), 12-13 November:** awake baseline 6.05 W (83 %).
      **Overnight 22:20-08:27, 608 min, battery, radios on: 1386 mAh =
      22.95 Wh = 2.27 W, `aosd`/`cxsd`/`ddr` 0 %**; the counters were
      already 0 at suspend, so nothing collapsed during that whole boot.
      Woke normally, no hang. So here (EL2, book4s kernel) DRIPS without
      CL5 gives no collapse and draws more than A (1.46 W): our claim in
      the thread holds on this machine, against #1315's SP11 report
      (Omarchy kernel with the CL5 drop, 99.9 %); EL and DT differences
      there are unknown. One night only. Summary: A 6.18 W awake / 1.46 W
      asleep / 0 %; B 5.97 / 0.70 / 100 %; C 6.05 / 2.27 / 0 %.
      **Why C draws more than A (13 November, read on the C boot after
      the night):** `pm_genpd/power-domain-system/idle_states`: DRIPS (S1)
      usage 0, **rejected 1 631 018 578**; SS1 (S0) usage 0, rejected
      11 698 198 while awake. CPU 0's `cpu-sleep-0` s2idle usage is
      1 630 954 791, the other CPUs' 2 to 31 976: one CPU asked TrustZone
      for DRIPS ~44 700 times a second all night and was refused every
      time. In OSI mode the topmost domain's parameter replaces the lower
      ones (`cpuidle-psci.c`), so the last CPU sends `0x0200c354`, which
      names cluster state 5, while the other two clusters were parked with
      CL4 (`0x01000044`): TrustZone refuses every system-level state, SS1
      included, unless the clusters are in CL5. A (no system state) parks
      in CL4 and stays there: no spin, 1.46 W. So at EL2 "DRIPS without
      CL5" is worse than no DRIPS, and anyone running linux-omarchy at EL2
      (slbounce, for KVM) gets this.
      **What that does not say: EL1.** Under Gunyah the request goes to the
      hypervisor, not TrustZone. linux-omarchy has had `domain_ss3` plus
      the CL5 drop since #975/#1315, and its README reports 99.9 %
      CX/AOSS/DDR on the Surface Pro 11 and all three states on a Yoga
      Slim 7x (7.3 with `2210`), booted from Omarchy's UKI (no slbounce in
      that chain, so almost certainly EL1; turbineBMW has not answered).
      So C-shape seems to collapse at EL1 on other machines.
      **Our "EL1 never collapses" is not established.** The one EL1 test of
      the sleep kernel (19 October ~16:00, `tools/experiments/sleep-test.sh`)
      loaded `qcom_adsp_pwr_lmts`, which crashed the ADSP at both suspends,
      and ran six hours before the VA/WSA macro votes (0024/0025) were
      found; at EL1 the ADSP always runs, so CX could not have collapsed
      then whatever Gunyah did. The 16 October "DSPs stopped" EL1 test
      predates the PDC, geni, LPASS, syscon and panel-supply fixes.
      **The EL1 run as planned would have been void:** the `el1-book4s`
      entry carries `clk_ignore_unused pd_ignore_unused` (live-iso's EL1
      arguments), and `book4-el2-sleep.service` is skipped at EL1, so no
      provider is synced and UFS has no hold. Use
      `tools/experiments/el1-sleep-prep.sh` (header: entry `el1-sleep`
      without the flags; icc_hold, cntv_arm, aoss_cxsd_only, forced
      sync_state; `status` after waking). Result decides whether the Book4
      can sleep deeply on a stock kernel.
      **Two daily (B) sleeps without collapse** in the log, 29 October
      11:59 and 3 November 13:34 (1.56 W): the Debian VM was set up on 28
      October and the Cutefish VM on 3 November (QEMU running that
      morning). Likely a KVM guest left running: its EL1 timers are what
      the firmware reads for the wake deadline (x1e-sleep: do not use
      el1tmr with guests running). To confirm: one sleep with `vm start`,
      one after `vm stop`. If so, the sleep hook should pause guests.
      **EL1 run done, 13 November: no collapse.** Entry `el1-sleep`
      (book4s, `book4-sleep.dtb`, no ignore_unused flags; black screen
      from GRUB to the login, then normal), "started at EL1", PDC
      pass-through, both DSPs started by Linux. Unprepared sleeps first
      (gcc unsynced): 48 min, 1.86 W, 0 %. Then
      `el1-sleep-prep.sh` (UFS hold, cntv_arm, AOSD off, 4 providers
      forced, none left unsynced) and 38 min on battery (13:20-13:58):
      **1.42 W, `aosd`/`cxsd`/`ddr` 0, `apss` 0**; resume clean. Read
      after it: DRIPS (S1) used 3 times, rejected 0, each CPU 3 s2idle
      entries (held, no spin); cntv_arm armed CNTV at 12 CPU_PM entries;
      ADSP and CDSP asleep throughout by their own counters; LPASS clock
      counts 0. **`apss` count 0 for the whole boot (3 h+)** although
      Gunyah accepted SS1 182 520 times and cluster CL5 1 238 785 times
      while awake: under the hypervisor the CPU subsystem itself never
      power-collapses on this machine, at runtime or in suspend, so
      nothing above it can. Same as Burch's XPS 13 at EL1 and our 19
      October run; now with the full fix set, so it stands. Open: why
      linux-omarchy reports collapse on the SP11 and Slim 7x (EL not
      confirmed; different firmware/Gunyah build; or their GMU driver and
      ADSP message, which we cannot test here). Deciding test: the Omarchy
      edge image booted live on this laptop, one suspend, `cxsd`. Also
      worth one read at EL2: does `apss` count while awake there?
      (`el1-sleep-prep.sh` had two bugs on the way: the wrong test-entry
      command, and `grep -q` in a pipe under pipefail failing the EL1
      check at EL1; both fixed.)
      **EL1 DEEP SLEEP REACHED, 13 November 14:28.** The blocker was ours:
      `cntv_arm` armed CNTV with its interrupt masked (copied from el1tmr,
      where TrustZone reads the raw register). Gunyah counts a vCPU timer
      only if it is enabled and unmasked (`arm_vm_timer_is_irq_enabled()`:
      ENABLE && !IMASK, public source) and drops a masked one at vCPU
      suspend, so it saw no wake deadline and never let APSS collapse.
      With `cntv_arm` arming it unmasked (same ~10-day deadline; 4db73fa,
      modules rebuilt, `el1-sleep-prep.sh cntv`), same boot, same prep:
      141 s asleep (14:28:04-14:30:25), **`apss`, `cxsd` and `ddr` each 1
      entry and 138.1 s = 97.9 %**, `aosd` 0 by design (aoss_cxsd_only),
      DRIPS used once, 0 rejected, both DSPs running, resume clean. So the
      Book4 reaches CX collapse and DDR self-refresh under Gunyah, with
      Samsung's firmware, CL5 kept. Stock s2idle cannot: `tick_freeze()`
      disables CNTV (Burch's finding on the XPS 13; there APSS collapsed
      but CX did not). Next: 1 h+ on battery at EL1 for the wattage
      (reload with `el1-sleep-prep.sh cntv` first: `status` removes the
      module); `masked=1` once as the control; x1e-crash at EL1; what of
      the prep a stock kernel lacks (forced sync_state, UFS hold); a
      proper form of the CNTV arming (in the arch timer or cpuidle-psci
      s2idle path) to offer upstream and to linux-omarchy.
      **EL1 wattage, 13 November 15:21-17:27:** 127 min on battery,
      radios on: 101 mAh = **0.77 W, `cxsd`/`ddr` 100.0 %**, resume
      clean. Within the gauge's error of B at EL2 (0.70 W; one 35 mAh
      step is 0.27 W over two hours), and against 1.42-1.86 W at EL1
      without the arming. So on this laptop EL1 sleeps as well as EL2.
      Reported in omarchy#15860 (discussioncomment-19594936), asking
      birkskyum for the Yoga's `apss` and what keeps CNTV armed there.
      **Plan from here (13 November):**
      1. On the EL1 boot, before leaving it: `el1-sleep-prep.sh cntv
         masked=1` + 2 min asleep (control: expect `apss` 0); x1e-crash
         (icecream95/x1e-crash bb344c4, `sync` first) for 10 min.
      2. ~~CL5 dropped at EL1 (Omarchy's shape)~~: dropped 13 November.
         Omarchy sleeps with `deep`, where cluster idle states play no
         part; its s2idle fails at EL1 anyway (CNTV); and with x1e-crash
         passing at EL1 birkskyum wants CL5 back. Only if he asks.
      3. The arming as a kernel patch, not a module (arch timer or the
         cpuidle-psci s2idle path, only when not in hyp mode), tested on
         book4s; then offer it on linux-arm-msm in Burch's thread and to
         linux-omarchy (owner's OK for each).
      4. What a stock kernel still lacks on the Book4: once the providers
         sync by themselves UFS fails on resume without a hold ("Forcing
         the sync breaks resume", power.md); check on the Omarchy edge
         image and tell birkskyum before anyone installs.
      5. The blog post "why it needed EL2" on nicolanicodemo.it is now
         wrong about EL1: correct it (owner's OK).
      6. Housekeeping: back to the daily EL2 entry (KVM, three weeks of
         use; EL1 had a 48 h reset on 14 October); `el2-dt-test.sh
         omshape undo`, `nocl5 undo`; keep `el1-sleep` until 1-3 are done;
         the table in power.md.
      7. Still open from before: the VM check, a Windows battery-standby
         figure, the ~0.7 W of the board.
      **birkskyum, 13 November 18:15 (discussioncomment-19597088):** the
      Yoga Slim 7x and the Surface Pro 11 numbers were `deep` (PSCI
      SYSTEM_SUSPEND, the default there: `s2idle [deep]`), not s2idle. On
      the Yoga at EL1 (7.3-59): deep 22.8 min, `apss` +22.8 min,
      `aosd`/`cxsd`/`ddr` 99 %; s2idle 30.5 min, `apss` +0.1 s, the rest 0,
      one system-domain entry, no rejection: the same as here without the
      arming. Nothing in 7.3 or their patches arms CNTV. So s2idle under
      Gunyah fails this way on every X1E machine tried, and
      SYSTEM_SUSPEND is how the others get down; C-shape at EL1 was never
      exercised. He asks: does the NP940XMA offer deep under Gunyah, and
      does B collapse through it without the module; and x1e-crash at EL1
      matters most (decides whether 2151 goes and CL5 comes back). Here:
      `mem_sleep` is `[s2idle] deep`; "`deep` never resumes" is from the
      first import (Fedora, Anatase kernel, EL1), never retried on the
      sleep kernel. If it still does not resume, a stock Omarchy on this
      laptop (default deep) would not wake. Next EL1 session, in this
      order: x1e-crash (built: `~/src/ext/x1e-crash/crash`, bb344c4),
      then one deep suspend of B with the prep and without cntv_arm
      (`echo deep | sudo tee /sys/power/mem_sleep`; hold power if it does
      not come back), then the `masked=1` control.
      **x1e-crash at EL1, 13 November 23:07-23:17:** `el1-sleep` boot
      ("started at EL1", "Broken DC ZVA" detected), prep in force, CL5
      in real use (cluster0 S1 used 86 319 times in 12 min, 23
      rejections). `crash` (bb344c4, `gcc -O2`) ran its 600 s under
      `timeout` with no reset and nothing in the kernel log; the round
      count was lost with the pipe (about 2.8 rounds/s measured after,
      so ~1700 rounds). Before 0043 it reset this machine within
      seconds. So the EL0 trap-and-emulate holds under Gunyah too.
      **`deep` at EL1, 13 November 23:21:19-23:23:24** (same boot, prep in
      force, `cntv_arm` removed: armed 0 times, `mem_sleep` deep): "PM:
      suspend entry (deep)", non-boot CPUs killed, **resumed cleanly**
      (lid; resume devices 1.3 s, no errors), `apss`/`cxsd`/`ddr` 1 entry
      each, 121.7 s of 125 s = **97.4 %**. So PSCI SYSTEM_SUSPEND works
      and collapses under Gunyah on this laptop without any timer help,
      as on the Yoga and the XPS 13, and "`deep` never resumes"
      (bootstrap.md, the first import) no longer holds on the sleep
      kernel. Not measured: wattage (2 min), `deep` at EL2, `deep`
      without the prep.
      **The arming as a kernel patch (written 13 November, NOT BUILT):**
      sleep-backport 0045, fork `book4/7.2-sleep` 10f75dbda:
      `arm_arch_timer.c`, in the existing CPU PM notifier: at
      CPU_PM_ENTER, if the virtual timer is disabled or masked, program
      `max_delta_ticks` ahead (2^56 ticks here, ~119 years) and restore
      CNTV_CTL at CPU_PM_EXIT; only when the driver uses the EL1 virtual
      timer and the machine is `qcom,x1e80100` (gated like the bcm2712
      workaround in the same file); boot line "arch_timer: idle CPUs keep
      a far timer deadline for the hypervisor". Not active at EL2.
      checkpatch --strict clean. `arm_arch_timer.c` is the same in v7.4-rc2
      apart from unrelated vdso lines, so the diff is the upstream one.
      Open: the module was only tested with 2^44 ticks; whether Gunyah
      takes a 2^56 deadline is checked by `el1-sleep-prep.sh cntv
      far_secs=3752999689` (2 min) or by the built kernel. Test: build
      (`build-sleep-kernel.sh`, incremental), boot `el1-sleep`, prep (it
      skips cntv_arm when the boot line is there), 2 min s2idle, `status`:
      `apss`/`cxsd` must count; then one EL2 boot and sleep as usual.
      Upstream: an RFC to linux-arm-msm and the timer maintainers, sent
      by the owner (the kernel's coding-assistants.rst: the assistant
      never sends, and adds no Signed-off-by), only after that test.
      **EL1 run (added 11 November):** stock Omarchy runs at EL1 under
      Gunyah (EL2 needs Microsoft's tcblaunch.exe plus DSP start by Linux).
      Here at EL1 (19 October) the system domain was entered once and held,
      no collapse. Elsewhere: Surface Pro 11 issue
      (dwhinham/archiso-aarch64-sp11#38): EL1 1.06 W, no CXSD, EL2 0.26 W.
      But #1315 (turbineBMW, SP11, Omarchy kernel, no slbounce mentioned in
      the PR or his repos, so probably EL1) got 0.25 W with four fixes our
      19 October EL1 test may have lacked: GMU driver so gcc reaches
      `sync_state()`, PCIe root ports allowed into D3 (7.3 d4c79b63d82d, not
      in our 7.2), geni force suspend (we have it, 0014), and the ADSP
      standby message (`qcom_adsp_pwr_lmts`: blacklisted here, it crashed
      our ADSP). Asked turbineBMW which EL (11 November, omarchy-pkgs#1315 comment 6790521071); watch for the answer. The Dell XPS EL1 thread, read in
      full 11 November (power.md): no CXSD/AOSD at EL1 there either (Burch
      0.43 W with every APPS vote zeroed; Packett DDR LPM only, via the
      qcrypto driver dropping the QCE boot vote). So #1315 is the only
      possible EL1 collapse on X1E, unconfirmed. For our EL1 run also
      record: apss/aosd/cxsd/ddr from `tools/power/suspend-test.sh`,
      `state_synced` of 100000.clock-controller, whether the crypto node is
      on, and that CNTV is armed (Burch: stock s2idle never collapses APSS
      at EL1 because `tick_freeze()` disarms CNTV; our `cntv_arm` covered
      that on 19 October). Test: boot "Arch Linux (7.2.7-book4) -
      test: el1-book4s" (B's sleep kernel and DT at EL1, never booted; if it
      hangs, hold power), one sleep of 1 h+ on battery, read the sleep log
      (`cxsd`, W). If no collapse, the gain needs EL2 or #1315's fixes. The sleep log called both sleeps of this
      boot (20:40, 21:42) `el2-sleep`; fixed in book4-sleep-log (reinstall
      with `install/arch/sleep-log.sh`), the two CSV rows stay mislabelled.
- [x] **EFI variables at EL2** (21 October): qseecom failed with -22, so no
      EFI variables, RTC offset, `efibootmgr` or `HibernateLocation`. SHM-bridge
      mode alone did not help; SHM bridges owned by Linux itself did (as on the
      Surface Pro 11, dwhinham/archiso-aarch64-sp11#38): sleep-backport
      0027/0028 and `qcom,shm-bridge-vmid` in the EL2 overlay. 199 variables,
      `rtc0` sets the clock at boot.
- [x] **Rebuild the sleep kernel** (21 October): 0024-0028 are in the kernel
      proper (Qualcomm's VA/WSA macro commits, the SoundWire IRQ fix, the SHM
      bridge self-owner); `~/audio-modules-prep.sh` (the module-only stopgap)
      is obsolete. `build-sleep-kernel.sh` now builds incrementally when
      patches are added at the end.
- [x] **Speakers, fingerprint and camera at EL2** (28 October): the sleep
      kernel's DTB is the Anatase base without `dts/patches`, so at EL2 only
      the woofers played (swapped, highs sent to absent tweeters: "audio is
      very low"), and the fingerprint reader and camera were missing. Now
      overlays (`dts/src/x1e80100-book4-edge-14-{speakers,fingerprint,camera}.dtso`)
      applied by `build-sleep-kernel.sh`, or `install/el2/sleep-dtb.sh
      [nocamera|restore]` for an installed kernel ([audio.md](audio.md)).
      **Works:** four amps attached, fingerprint `1c7a:05a1` enumerates, camera
      streams (`cam`, ~40 fps, no SMMU faults; first time at EL2), and deep
      sleep holds (141 s suspend: `cxsd`/`ddr` 98 %). Speaker limiter +6 ->
      +9 dB. Seen twice on 28 Oct: `SWR bus clsh detected` on 6b10000 when
      playback starts; recovers by itself.
- [x] **Hardware video decoding at EL2** (25 October): Moonlight found no
      V4L2 decoder because there was none: the video clock controller driver
      was never built (`CONFIG_SM_VIDEOCC_8550`) and the EL2 overlay disabled
      Iris, since at EL2 nothing authenticates and starts its firmware. Fix:
      sleep-backport 0040 (Stephan Gerhold's non-TZ Iris start, ported from
      venus; loads `qcom/vpu/vpu30_p4.mbn` without TrustZone), the firmware
      stream (SID 0x1942, jglathe via justririll/x1e-dsp) in
      `dts/src/x1-el2-book4.dtso`, both modules in `build-sleep-kernel.sh`.
      **Works** (`tools/video/iris-test.sh`): `/dev/video0` decoder,
      `/dev/video1` encoder, no reset, no SMMU faults; 1080p60 H.264 and HEVC
      output bit-identical to software (PSNR inf), ~0.3 s CPU per 10 s clip
      against 2.3 s (H.264) / 3.3 s (HEVC) in software. s2idle with Iris
      loaded (idle) still collapses: cxsd/ddr 1 entry, 136.5 s of a 139 s
      suspend (aosd 0 by design, `aoss_cxsd_only`). Still to check: Moonlight.
- [ ] **NPU (Hexagon CDSP) from Linux** (25 October, half way): FastRPC
      works at EL2. Recipe from armbrusl/x1e-npu: Samsung's shells from the
      Windows CDSP package `qcnspmcdm_ext_cdsp8380` (build
      `CDSP.HT.2.9.c1-00078-HAMOA-1`, byte-identical firmware to what qebspil
      boots), fastrpc host library built into `~/npu/rt`, llama.cpp's
      prebuilt `linux-arm64-snapdragon` package (b11874, has
      `libggml-htp-v73.so`; no x86 cross-build needed), group `fastrpc` +
      udev rule (`~/npu-setup.sh`). The unsigned PD starts and loads the HTP
      library, then llama.cpp's first `dspqueue` round trip never returns:
      qualcomm/fastrpc#377, same hang on a T14s with the same c1-00078
      firmware; the working Yoga ran a c2 build. Killing the hung run and
      starting another crashed the CDSP (`fatal error ... sleep_statsi.c:537`)
      and remoteproc recovery oopsed (attach-only DSP, no start op): recovery
      is now disabled at EL2 by `install/el2/sleep-setup.sh`. After any hung
      NPU run: reboot before the next. No newer Samsung driver on Windows
      Update (NPU driver 30.0.219.1000, 9 Nov 2025 = c1-00078).
      **Root cause of the hang (25 October):** this firmware's DSP-side
      dspqueue has a "Queue Monitor" (DSP log: `dspqueue_import: Queue
      Monitor supported. Importing Queue ... requires packet_callback`) and
      supports kernel "dspsignal" doorbells (capability 130 = 1); mainline's
      fastrpc driver has no dspsignal (259 = 0; the fastrpc userspace stubs
      the ioctls out as unsupported), so the CPU falls back to one FastRPC
      call per packet, which the monitor never acts on. Forcing a version 1
      queue (fastrpc branch `book4-dspqueue-v1` in `~/npu/fastrpc`,
      `DSPQUEUE_FORCE_V1=1`) hangs the same way. The Yoga that works runs
      the older `c2-00051` (no Queue Monitor). DSP logs: put `0x1f` into
      `<dsp dir>/<program>.farf`. Fix = dspsignal in the kernel driver and
      the userspace ioctls (Qualcomm's downstream adsprpc has it), or a
      DSP-side workaround in libggml-htp. A hung NPU run is not harmless:
      the forced-v1 run (stopped by SIGINT at 16:21:28, then `No context ID
      matches response`) was followed by a hard reset at 16:24 with nothing
      logged, as the T14s owner warns (late DSP reply on a torn-down
      session). So: no more NPU runs that can hang until dspsignal exists;
      after a hang, reboot at once.
      **dspsignal port written (25 October, untested):** sleep-backport 0041
      (Qualcomm dsp-kernel's dspsignal on upstream fastrpc: 8-byte
      `client_id << 32 | signal` messages both ways, local ioctl 'R' 0x60)
      and the fastrpc library side (`tools/npu/fastrpc-patches/`, built into
      `~/npu/rt`; probes the kernel, so it is inert on older kernels). Test:
      rebuild + `install/el2/sleep-setup.sh`, reboot, then
      `bash tools/npu/dspsignal-test.sh` (checks both capabilities are 1
      before it runs llama.cpp).
- [ ] **An overnight drain** for a real wattage: the EC's `charge_now` moves
      in ~35 mAh steps, so an hour gives only "roughly 1 W" (0.5-1.5 W).
- [ ] **Why AOSD resets** (x1e-sleep's open issue too): PS_HOLD hard reset
      at N hours + ~1 min after boot. Not ours to solve alone; follow
      x1e-sleep and #94.
- [ ] **Verify sleep-backport 0024/0025** (upstream's VA/WSA macro commits
      in place of our first versions): both LPASS vote counts 0 when idle,
      the collapse as before, sound working.
- [ ] **Run `install/arch/boot-cleanup.sh`**: drop the October test entries,
      the PDC test kernel and unused test DTBs.
- [ ] **Primary USB-C controller fails after sleep** (7 November, 18:38;
      not investigated). A USB stick wasn't detected on that port:
      `a600000.usb` (`dwc3-qcom`) was in runtime PM `error`, `usb2`/`usb3`
      logged "can't set config #1, error -16", and
      `gcc_usb3_prim_phy_pipe_clk` warned "already disabled" and "already
      unprepared". The same clock warnings appeared during `systemd-sleep` on
      4 November (17:36), so they are likely the source of the `W` taint flag.
      `a200000.usb` and `a800000.usb` worked, and the stick worked on the
      other port. Reboot to recover. Next: find whether it fails on every
      resume, and which sleep change (sleep-backport, DTS) touches this
      controller's clock.
- [ ] **Move off 7.2, revisit at 7.4** (owner's decision, 5 November: no
      kernel move for now). Trigger: 7.4 is released and announced as
      long-term (expected 20 or 27 December 2026, may slip to January; not
      confirmed). Idea: a branch from stable, without Anatase, carrying our
      patches plus the Samsung drivers and device tree, on a test boot entry
      first. Findings to reuse (5 November):
      - 7.2 is end of life (last release 7.2.15). Our `anatase-7.2` base's
        Makefile history stops at 7.2.7, and Anatase had no 7.3 branch.
      - Of the 56 commits in `anatase-7.2..book4/7.2-sleep`, 15 are in v7.3 by
        exact subject (PDC, LPASS macros, geni). The other 41 had no match, so
        a reworded patch could be among them.
      - Needed from Anatase: `samsung-galaxybook-ec.c`, `samsung-emuec.c`, the
        `x1-samsung-*` device tree, and in-file patches such as the QSEECOM
        allowlist. Only file names were compared, so a full diff is still to do.
      - Check whether upstream's `qcom_q6v5_pas` late attach support (v7.3) can
        replace our remoteproc attach patches.
- [ ] **Hibernation resume resets the machine** (EL1): `pm_test` plan in
      [power.md](power.md); low priority now that s2idle sleeps deeply.
- [ ] **Fedora's role** (undecided): build host only, or retire it and move
      `/boot`, GRUB and the kernel builds to Arch.
- [ ] **The board's power in deep sleep: ~0.9 W** (sleep log, 21-23 October:
      0.90 W over 4 h 10 min on el2-sleep, `cxsd` 100 %; nights of 12 h
      survive; the Vivobook S15 is at ~0.17-0.25 W, the Surface Pro 11 at
      0.26 W). Every sleep is logged with its entry and radio state
      (`install/arch/sleep-log.sh`, `journalctl -t book4-sleep`).
      **GPIO 44 (`MODS`) ruled out:** el2-mods ~0.93 W (1 h 36 min) against
      ~0.9 W on el2-sleep. Next, each with no rebuild: airplane mode before
      a sleep (the log records it); `tools/power/el2-dt-test.sh nomisc`
      (touchscreen rail switched off at suspend). Further candidates: `VREG_MISC_3P3` (touchscreen) and `VREG_WCN_3P3`
      (Wi-Fi/BT chip, held only by always-on on the 14") are always-on; so
      are l7b/l10b (front camera supplies; the driver could switch them) and
      l12b (1.2 V, no consumer on the 14"; speaker-amp vdd-io on the 15", so
      test it last). A Windows battery-standby figure (one hour
      lid closed, `powercfg /sleepstudy`) would give the target.

## Test of 10 October (DT 0005/0006, emuec orientation 0005)

- [x] DT 0005/0006 (Fedora, "alt DT woofer-names.dtb"): new DT running,
      repeater 0x43 gone, speakers from the right sides, fingerprint `1c7a`
      present. Made the default (`book4-default-1010.dtb`, previous default
      as the alt entry); UCM woofer order flipped; on the kernel branch
      `book4/7.2` (f53908232). (The test's step 1 printed no names: it asked
      `amixer -c0`, where UCM's remap hides them; `-D hw:0` shows them.)
- [x] emuec orientation: now `drivers/anatase/patches/0004` (rebased onto the
      tree's driver; on `book4/7.2` as 6221fc739). Retest after installing it:
      charger `reverse` / rotated `normal`, hub `normal` / rotated `reverse`;
      the SBU mux select (GPIO 167) follows, enable (168, active low) on.
- [ ] External monitor through the USB-C hub: still no picture **in both
      orientations**, so orientation was not the blocker. DP alt mode is
      entered and configured (pin D, all VDMs ACKed), HPD reaches msm_dp
      (`bridge_hpd status=1`), then every DPCD read times out
      (`dpu_dp_aux: 0x00102 AUX -> (ret=-110)`). Suspects: which DP
      controller / AUX the port is really wired to, the SBU mux polarity, the
      PHY. Captures: `~/usbc-dp-20261010-1822*.log`, `...-1823*.log`.

To test (should work, never verified)

- [x] **CPU frequency scaling on Fedora** (5 Oct): `scmi-cpufreq` via
      `/etc/modules-load.d/book4-cpufreq.conf`, 710-3417 MHz, sha256 x2.9
      ([power.md](power.md)).
- [x] **Power profiles do nothing**: `power-profiles-daemon` has only its
      placeholder backend. The Samsung EC profiles were measured by hand
      (5 Oct, [power.md](power.md)): no difference in a 60 s all-core load.
      Left as is.
- [ ] **Headset microphone** on the jack. Headphone playback works with
      automatic switching (5 Oct, Arch), as do digital USB-C earphones and
      Bluetooth earbuds (A2DP AAC); see [audio.md](audio.md).
- [ ] **External monitor**: USB-C DisplayPort (DP alt-mode via `samsung-emuec`)
      and HDMI (`rtd2171` bridge, `simple_bridge`). **HDMI port works**
      (8 Oct, Arch): AOC 27" at 2560x1440 @ 60 Hz, hot-plug detected, picture
      fine (Hyprland gave it scale 2: set a per-monitor scale). Across
      suspend/resume not yet checked. Also the last open check
      for the sleep fix (`patches/0002`): a display still works after resume.
      **6 Oct, Arch: USB-C to HDMI hub (VIA VL817, Billboard) does not work.**
      `samsung-emuec 1-0033: DisplayPort Alt Mode configured with pin D`, the
      USB controller restarted and the hub's USB side (card reader) came up,
      but no HPD, no link training, not one `msm_dp` message; DP-1/DP-2 stayed
      disconnected and the hub then exposed its Billboard device. The break is
      between Alt Mode entry and the display driver: DP Status/Attention ->
      HPD in `samsung-emuec`, the DRM bridge, or the hub. Next: retest with
      `samsung_emuec` dynamic debug and `drm.debug=0x106`, monitor on and
      connected to the hub before plugging it in; also the other port and a
      direct USB-C-to-DP/HDMI cable. Same driver on Fedora.
      **8 Oct, Arch, traced (`tools/display/usbc-dp-capture.sh`):** the
      whole Alt Mode sequence is ACKed (SVID, modes, enter, status,
      configure, attention), HPD = 1 reaches `msm_dp` (DP-1, 2 s after
      plug-in), then **every AUX read times out (-110)** and after ~8 s
      `msm_dp` gives up ("failed to read caps"); the hub then shows its
      Billboard. Orientation was "reverse". AUX runs over SBU through the
      FSUSB42 mux (`usb-1-ss0-sbu-mux`, enable TLMM 168, select 167): next,
      flip the plug (orientation polarity) and read the mux GPIOs.
      Flip test (8 Oct, 11:16 and 11:17, plug rotated in between): sysfs
      orientation reads **"reverse" both ways** (4 of 4 plug-ins), AUX
      fails both ways. So samsung-emuec's orientation decoding (CC_STATUS
      0x11 bits 7:4) is wrong or that field is not orientation; the SBU mux
      then always selects the same way (ss0: enable 168 low, select 167
      high). AUX failing in *both* orientations suggests a second fault
      too. Next (parked, HDMI port covers external displays): raw bytes
      for both orientations with `sudo python3 tools/display/pdic-cc.py 1
      watch`, fix the decoding, retest.
      **Cause found (9 Oct):** CC_STATUS (0x11) bits 7:4 are the attach
      type / power direction, not the orientation: the charger (laptop
      sink) reads 1 ("normal") with the plug either way round, the hub
      (laptop source) 2 ("reverse") either way. So with a hub or monitor
      the SBU mux and combo PHY are always set for "reverse". Next: find
      the real orientation bits (`pdic-cc.py 1 watch`, charger flipped),
      then fix `samsung-emuec` (and report to Anatase). AUX also failed
      in the matching orientation, so a second fault remains.
      **8 Oct, Windows: the same hub works on the same port** (picture,
      card reader). The hub's Billboard reports DP alt mode (SVID 0xFF01)
      entered with configuration status 0x3 ("configured successfully"), so
      the hub is fine and the fault is on the Linux side; compare with
      `lsusb -v` of the Billboard on Linux (`bmConfigured`). The firmware's
      ACPI logs only role reads (`GDRO`/`GPRO`) during it. Also logged:
      `SMC arrived with function code 4200010a` with parameters `2 1 2a`,
      `2 1 9`, `2 2 9`, 3.2 s after plug-in and again 2.4 s after unplug,
      i.e. at display bring-up and teardown. Reading 0x4200010a as Qualcomm
      SiP service 1 (boot), command 0x0a, that would be
      `QCOM_SCM_BOOT_SET_REMOTE_STATE` (2 arguments: state 1/2, id 0x2a and
      9). Unverified, but worth checking whether Linux's DP path makes (or
      needs) such a call. Raw captures: `C:\scdt\hub1.etl`,
      `dbgview-hub1.log` (Samsung driver WPP events there are undecoded).
- [ ] **The sleep fix in long-term use** (installed 4 Oct, Fedora and Arch):
      repeated cycles, plug-in and unplug during sleep, over days.
- [ ] **Unplug reset back at EL2 (22 Oct):** the daily kernel 7.2.7-book4s
      had none of `drivers/anatase/patches/0001-0003` (they reached
      7.2.7-book4 only as a module build, never `~/src/patchwork`'s source),
      so a charger unplugged in sleep hard-reset the machine (RTC back at
      2024-05-29). Fix: `tools/kernel/update-sleep-emuec.sh`;
      `build-sleep-kernel.sh` now applies and checks them. Test at EL2: plug
      in during sleep (wakes, resleeps), unplug during sleep (no reset),
      `pm: quiesced` in the log.
- [ ] **Battery readings frozen on book4s (22 Oct):** same cause for
      `drivers/anatase/patches-galaxybook-ec/0001` (refresh on read): at 9 %
      the battery showed "Charging", 374 mA, unchanged for 16+ minutes.
      Fix: `tools/kernel/update-sleep-galaxybook-ec.sh`;
      `build-sleep-kernel.sh` applies and checks it too. Then retest awake
      charging below 50 % (it was ~5 W).
- [ ] **Fedora kernel update** (7.2.8 and later): only affects the fallback
      "(other)" entry, kernel packages are held back. When taken: DKMS modules
      built, display/battery/Wi-Fi/audio fine on that entry. See
      [updates.md](updates.md).
- [ ] **GRUB guard on a future GRUB update**, including the `chain.mod` copy
      for the Windows entry (the guard was tested before that entry existed).
- [ ] **Wi-Fi after a firmware update** (`linux-firmware`/`atheros-firmware`):
      a new `board-2.bin` could change which board data ath12k uses.
- [ ] **`install/install-fedora.sh` end to end** on a fresh install (each step
      was tested on its own, the script as a whole never).
- [ ] **Touchscreen** on GNOME and on the Fedora kernel (works under KDE and
      Hyprland on the Anatase kernel). The two "UNKNOWN" HID interfaces are
      **Goodix vendor channels, not pen or gestures** (Windows, 8 Oct): the
      Goodix `27c6:0123` has three collections, COL01 touch screen (0x0D/0x04:
      tip, contact ID, X 0-28800, Y 0-18000, contact count, max 10 contacts,
      a 256-byte certification blob), COL02 vendor page 0xFFF0 and COL03
      0xFFF1 (64-byte in/out reports, firmware/debug). No pen collection.
      Windows binds only the generic `input.inf` to COL02/03. Nothing to do.

## Open problems

- [ ] **CPU boost** (`/sys/devices/system/cpu/cpufreq/boost` = 0): try 4 GHz
      single/dual-core boost; watch temperature and battery. Windows,
      8 Oct ([tools/power/cpu-clock.py](../tools/power/cpu-clock.py): a
      chain of dependent adds, clock without counters; Windows' own
      counters read a flat 1851 MHz and are not usable):

      | Windows | one core busy | all 12 busy |
      |---|---|---|
      | battery, Balanced | ~2510 MHz, every cluster | ~2510 MHz |
      | **AC, "Best performance" mode** | **~4005 MHz on CPUs 4-11**, ~3410 on CPUs 0-3 | ~3417 MHz |

      Linux, 8 Oct (Arch, AC): policies 4 and 8 list
      `scaling_boost_frequencies` 4012800 (policy 0 none, as in Windows).
      `boost` = 1 raises `scaling_max_freq` to 4012800, but schedutil never
      requests it (one core busy: 3417.6 MHz, 0 s at 4012800 in
      `time_in_state`). Forced with `scaling_min_freq` = 4012800, CPUs 4-5
      measure **3996 MHz**, 48 C: the hardware boosts. Cause: schedutil
      scales to the reference frequency recorded once at policy creation,
      when boost was off (3417.6 MHz); no module or cpufreq parameter
      changes that, and it is not updated later. Needs a kernel change
      (scmi-cpufreq creating its policies with boost enabled, so the
      reference is 4012.8 MHz) in our branch, plus boost off on battery
      (as Windows) via a rule on AC changes. Alternative without a kernel
      change: `ondemand` on policies 4/8 (loses schedutil's energy-aware
      scheduling).

      So the 4 GHz boost is real, on the second and third clusters only
      (CPU 0-3 tops out at the 3417.6 MHz step), single-core, on AC.
      (Battery figures corrected by 100/102 like the tool; the AC
      all-core reading matches the 3417.6 MHz step exactly.) Next, on
      Linux: `echo 1 > /sys/devices/system/cpu/cpufreq/boost`, check that
      `scaling_max_freq` of `policy4`/`policy8` rises above 3417600, then
      `python3 tools/power/cpu-clock.py 4 8` (expect ~4000) and watch the
      temperature; the boot log's "Failed to add opps_by_lvl at 3417600 for
      NCC1/NCC2" may be related.

      **23 October: fixed in sleep-backport 0037** (scmi-cpufreq creates its
      policies with boost enabled, so the reference is 4012.8 MHz; the order
      in cpufreq_policy_online is init -> table validation -> CREATE_POLICY
      notifier -> boost applied). Boost on the charger only, as Windows:
      `userspace/battery/91-book4-boost.rules` via `install/arch/battery-policy.sh`.
      To verify after the next sleep kernel build, on AC:
      `python3 tools/power/cpu-clock.py 4 8` should read ~4000 MHz.
- [ ] **Charging stalls after plugging in while awake** (6-7 Oct): first PD
      request times out, 5 V, then 20 V; the battery then gets ~1 W. Plugged
      in during sleep it charges fine. Workaround: plug in with the lid
      closed. Test with `tools/power/charge-test.sh`; fix ideas (grace period
      before the first request; EC `CableDetect`) in
      [power.md](power.md#charging-stalls-after-a-plug-in-while-awake-6-7-october-2026).
      Fix A drafted (untested): `patches-experimental/0004`, steps in
      [handoff-fedora-next.md](handoff-fedora-next.md#4-charging-after-a-plug-in-while-awake-written-7-october-on-arch).
      If 0004 is not enough: [handoff-windows-scdt.md](handoff-windows-scdt.md)
      (does Windows call the firmware's `SCDT`, "set cable detect"?).
- [ ] **Spontaneous reset at 47 h 59 min of uptime** (14 Oct, Arch, wall
      clock including suspend; no log, no pstore). Suspect: a timer in
      Qualcomm's hypervisor, which Windows never runs. Test: one boot at
      EL2 (no hypervisor) kept up past 48 h; [el2.md](el2.md).
- [x] **Suspend drain: the SoC never reached deep sleep** (3.1-3.8 W).
      **Solved at EL2 (19 October):** `el1tmr`, the 7.3 PDC/LPASS/geni
      fixes, the panel supplies and the VA/WSA macro votes; 97.5-99.9 % in
      `aosd`/`cxsd`/`ddr`, 1.55 W without the DSPs. Daily since 20 October
      (`install/el2/sleep-setup.sh`). **At EL1 under Gunyah too since 13
      November** (CL5/DRIPS item): it needed CNTV armed unmasked in
      s2idle; 97.9 % `cxsd`/`ddr` in a first 141 s sleep. The rest of the board's power is under "Now" above;
      everything tried on the way: [power.md](power.md).
- [ ] **UFS `ref_clk` leak fix for 7.3**: fixed upstream by Qualcomm's
      `f07317a8d57f`, queued for 7.4 without `Cc: stable`. After 7.4-rc1:
      stable backport request (email to stable@vger.kernel.org) or ask the
      Anatase kernel to cherry-pick it. Our kernel carries our own patch
      meanwhile ([power.md](power.md)).
- [x] **Sustained full load reaches 108-112 C** (23 October, on the charger,
      boost on): llama-server reading opencode's 11.4k-token prompt on all
      12 cores for ~20 min. Prompt reading fell from ~65 to ~9 t/s, the
      hardware throttling the clocks while cpufreq still showed 4012 MHz;
      the Linux cpufreq cooling devices stayed at state 0, so only the
      firmware limits it (1-minute runs on 5 October peaked at 96 C). 81-83 C
      20 s after stopping. sleep-backport 0039: a passive trip at 95 C on
      all 30 CPU/CPUSS zones, bound to each cluster's cpufreq cooling
      device (as the GPU zones are). Verified 24 October, on the charger
      with boost: 5 min of `openssl speed -multi 12 sha256` held the hottest
      CPU sensor at 95-97 C (step_wise moving the clusters between ~1-4 GHz,
      single samples down to 710 MHz), 78 C seconds after; 26.1 GB/s
      averaged (29.0 GB/s for 60 s unthrottled on 5 October). The
      ACPI tables (Windows) also limit on board thermistors behind the PMIC
      ADC (TZ31/TZ32, passive 59/63 C), which Linux does not describe.
- [x] **UFS speed** (24 October, `fio`, 4 GB NOCOW file on btrfs, on the
      charger): KIOXIA THGJFJT2T85BAT0A, UFS 4.0 (spec 0x0400), 2 lanes.
      Sequential 1 MB QD32: read **1.8 GB/s** (raw disk and file alike;
      `dd` buffered 1.8 GB/s), write 1.57-1.59 GB/s; random 4K: 8,445 /
      3,307 IOPS at QD1 (90 / 84 us), 91,220 / 48,048 at QD32. Nothing to fix:
      - The link runs at HS-G4 (rate A), the most X1E allows: its GCC has
        no 403 MHz UniPro rate, which ufs-qcom needs for G5 (300 MHz = G4;
        PHY and device support G5; SM8650 has the 403 MHz OPP, X1E and
        SM8550 stop at 300). Clock scaling off changed nothing.
      - WriteBooster works: ufs-qcom sets UFSHCD_CAP_WB_WITH_CLK_SCALING, so
        it is on while the clock is scaled up (`flags/wb_enable` true during
        writes) and off at idle; buffer 0x2000 units, 100 % available, wear
        0-10 %.
      - A first reading of ~0.9-1.05 GB/s for the file was not btrfs: the
        random-4K write tests had just scattered it inside the UFS's own
        flash mapping. Rewritten sequentially it reads at 1.8 GB/s; after
        20 s of random 4K writes over it, 1.1 GB/s again (reproduced).
- [ ] **Hibernation** (setup removed 24 October with `hibernate-setup.sh undo`:
      swap file, `/swap` subvolume and the DSP service; zram only now. Possible
      at EL2 too since EFI variables work there,
      21 October; with deep sleep at EL2 it is no longer needed for nights on
      battery, and its resume still resets the machine). Swap and
      `HibernateLocation` are set up. The first attempt hung while stopping
      the DSPs after the user session froze; moving that stop before the
      freeze resolved the hang. The second attempt reached hibernation entry
      but reset before writing a usable image. Next: use `pm_test` stages
      (`freezer`, `devices`, `platform`, `processors`, `core`, `test_resume`)
      to isolate the reset, then retry a full hibernate and validate restore
      before installing the lid policy. See [power.md](power.md#hibernation-the-practical-fix).
      No timed wake exists (RTC has no alarm; EC wake timer tested 8 Oct:
      no wake). Never boot Fedora while Arch is hibernated (shared btrfs).
- [x] **Charger plugged in during sleep now charges** (`patches/0003`,
      5 Oct, Fedora): wakes, negotiates, sleeps again. Same on
      Arch/Omarchy (5 Oct): logind re-suspends 29 s after the wake.
      Sent to Anatase as a follow-up on #3.
- [ ] **Camera**: libcamera tuning (washed-out colours; ciscobugger has an
      OV02C10 sensor helper), and the power cost of the always-on GPIO hogs.
- [x] **Four speakers** (5 Oct): default DTB `four-speakers.dtb`
      (`install/speakers-default.sh`), UCM + PipeWire crossover and limiter
      ([audio.md](audio.md#four-speakers-5-october)). On Arch too
      (`install/arch/sync-audio.sh`, checked 5 Oct). DT sent to Anatase as #4.
- [ ] **Fingerprint reader** (8 Oct): works on Fedora. EgisTec `1c7a:05a1`
      (ETU905A80-E, firmware 9050.1.2.32) in the power button, on `usb_2`
      ([dts/patches/0004](../dts/patches); default DTB via
      `install/fingerprint.sh`, also on the kernel branch). Two userspace
      needs: USB autosuspend off (it dropped off the bus while enrolling;
      `userspace/fingerprint/`), and SDCP in libfprint, without which the
      sensor drops every print (verify finds 0 on the chip, fprintd deletes
      the enrolment): libfprint MR !547 (unmerged, head `2d7c5277`) built as
      Fedora's RPM by `install/fingerprint-libfprint.sh`, version-locked.
      sudo authenticates by finger; the KDE lock screen claims the sensor and
      waits (seen in fprintd's log) but an unlock by finger is not confirmed:
      rest the finger, a click is a power-key press. Sent to Anatase as #5. Arch: `install/arch/sync-fingerprint.sh` ran to the end (8 Oct); **sudo works on Arch** (8 Oct,
      `libfprint-sdcp` provides/conflicts `libfprint`, so updates keep it).
      Never run `omarchy-setup-security-fingerprint` (replaces
      libfprint-sdcp with libfprint-git); the lock-screen PAM file is
      written by `sync-fingerprint.sh` step 8 or `sudo omarchy-apply-lock`.
      **Lock screen by fingerprint works on Arch** (8 Oct, after
      `sudo omarchy-apply-lock`). **Booting Windows wiped the print from
      the sensor chip** (8 Oct, 20:39: "Print was not found on the devices
      storage"; fprintd then deleted Arch's record). Recovery: enroll on
      Arch, copy /var/lib/fprint/$USER into Fedora's root subvolume,
      `restorecon -R /var/lib/fprint` on Fedora. To check: whether removing
      the Windows Hello fingerprint stops the wipe. Left: drop the local
      builds once !547 is in Fedora's and Arch's libfprint.
- [ ] **DT cleanup: `eusb5_repeater` (PTN3222 at I2C 5 / 0x43) is enabled
      but probably absent.** Windows' DSDT has only the 0x4F repeater (used
      by usb_2, the fingerprint) and three USB controllers (USB0/USB1 =
      the USB-C ports, USB4 = usb_2); no USB-A port, `usb_mp` correctly
      off. Nothing references the 0x43 node, so it is harmless; disable it
      in the next board DT patch (found with `tools/kernel/dt-graph.py`, 9 Oct).
      Why it is there: Anatase's "enable USB-A only on 16-inch model"
      (3f20abc5e, 30 Sep): the 16" has a USB-A port, and this repeater is
      its; the shared dtsi still enables it for both. Patch 0006
      (`tools/kernel/woofer-names-dtb.sh`) disables it on the 14".
      Anatase upstream checked 10 Oct: no Samsung changes since 30 Sep,
      issues #1-#5 unanswered.
- [ ] **CDSP channels fail at boot** on every boot, both kernels, Fedora and
      Arch: `fastrpc` / `qcom_smd_qrtr` on `32300000.remoteproc` "failed to
      create endpoint" (-12), together with a `qcom-apm` "CMD timeout". No
      visible effect so far. Details in [arch.md](arch.md).
- [ ] **GPIO 44 (MODS)**: the firmware's Modern Standby "display off/on"
      signal to the EC, reserved in the DTS. Not needed for the unplug fix,
      but it changes how the EC handles power events in sleep; worth
      revisiting together with the drain. [power.md](power.md).
- [x] `deep` suspend never resumes: no longer true on the sleep kernel at
      EL1 (13 November: resumed, `cxsd` 97.4 %; CL5/DRIPS item). Untested at
      EL2.
- [x] EC word at `0xb6` (37 on this unit) is **not** the cycle count: the
      DSDT's `_BIX` reads it from `CYLC`, EC offset **0xD0** (16 bit, high
      byte first); Windows reports 105 cycles (8 Oct). What 0xB6 is stays
      open. [ec-protocol.md](ec-protocol.md).

## Kernel

- [x] **Public kernel branch** (6 Oct):
      https://github.com/n1c0la84/linux-book4-edge/tree/book4/7.2 (Anatase
      base + our device tree and samsung-emuec patches + `book4_edge_defconfig`),
      checked against what runs ([kernel.md](kernel.md#our-branch-n1c0la84linux-book4-edge-6-october)).
- [ ] **Arch `linux-book4` PKGBUILD** from that branch, so Arch gets a real
      kernel package instead of modules copied from Fedora.
- [ ] **Installer stick for other owners** (planned 6 Oct). A newcomer has
      only Windows: they need our kernel and device tree (public branch), a
      GRUB with `cutmem`, the devicetree line and our kernel parameters,
      **their own firmware extracted from their Windows partition** (not
      redistributable: DSP images, GPU, Wi-Fi board data, `firmware.md`), an
      initramfs that boots from USB (solved in `rescue-usb.sh`) and our
      userspace settings. `rescue-usb.sh` builds such a stick but takes the
      kernel, DTB, firmware and settings from this running machine. Next:
      a "from scratch" mode that runs on any Linux PC (kernel from the
      branch, cross-built or as a published package; Arch Linux ARM set up
      under `qemu-user`, as omarchy-snapdragon does), plus a first-boot
      script that copies the firmware from the internal Windows partition;
      then install Fedora or Arch/Omarchy from the stick with our scripts.
      Prerequisite: boot-test the rescue stick (it proves the boot loader and
      the USB initramfs).

## Upstream

Details in [upstream.md](upstream.md).

Waiting for a reply (Anatase, `anatase-org/kernel-anatase`):

- [ ] #1 PD request retry after hot plug (+ cycle-count register note).
- [ ] #2 Front camera and privacy LED, device tree.
- [ ] #3 Machine reset when the charger is unplugged during sleep.

Not yet reported:

- [ ] ath12k / linux-firmware: WCN7850 firmware c7-00108 regression on this card.
- [ ] systemd/libinput: keyboard tagged as tablet pad. Likely cause, from
      the HID caps in Windows (8 Oct): the ENE `0cf2:9050` has five
      collections, keyboard, consumer, vendor 0xFF00 (256-usage array),
      wireless radio controls, and a **System Control collection whose
      input carries Button page usages 1-2**. Linux merges them into one
      "Keyboard" input node; those two buttons should become BTN_0/BTN_1,
      which `input_id` reads as tablet-pad buttons. To confirm on Linux:
      the node's KEY bitmap (`/proc/bus/input/devices`, bits 0x100/0x101)
      and `/sys/bus/hid/devices/*0CF2:9050*/report_descriptor`. A hwdb
      entry or a HID quirk that drops those usages would fix it for
      everyone.
      Confirmed on Linux (8 Oct, Arch, Anatase kernel): report descriptor
      has System Control (`05 01 09 80`), report 0x0D, Button usages 1-2
      (`05 09 19 01 29 02`); the node gets KEY bits 0x100/0x101 (BTN_0/1).
      With Anatase's HID quirk the device is split into separate nodes and
      nothing is mis-tagged (systemd 262: keyboard node `ID_INPUT_KEYBOARD`,
      System Control node only `ID_INPUT`). The tablet-pad tag happens only
      on kernels without the quirk (one merged "Keyboard" node, e.g.
      Fedora's stock fallback). Upstream fix to propose and test there: a
      `60-input-id.hwdb` entry for `0cf2:9050` (keyboard, not tablet pad).
- [ ] Saddytech driver: design/last-full swapped, rate sign. Windows
      (8 Oct) confirms our mapping: design 54 801 mWh = 0xB0 (3531 mAh) x
      15.52 V, full charge 55 872 mWh = 0xB2 (3600 mAh) x 15.52 V; `_BST`
      treats the rate as signed 16 bit and reports its absolute value.
- [ ] linux-arm-msm DTS thread: `pmic-glink` cannot work with this firmware
      image (and, if wanted, a tester's report on the v6 series).
- [ ] Help get `samsung-galaxybook-ec` and `samsung-emuec` to mainline, even
      only as a tester. Until they land, every distribution needs a patched
      kernel for this laptop.

## Arch and Omarchy

- [ ] **Make the Arch/Omarchy setup reproducible end to end**: the whole
      order is in [install.md](install.md) (20 October), every step a script;
      the sequence has never run on an empty disk, and
      `stage3-omarchy-install.sh` as a whole has not been run. [arch.md](arch.md).
- [ ] **Rescue USB stick** (`install/arch/rescue-usb.sh`): a generic live
      USB cannot boot this machine (no `cutmem`, no device tree, no Anatase
      drivers). **Built 6 Oct** on a 64 GB stick (first run stopped at an
      expired sudo prompt; the script now keeps sudo alive and resumes on a
      stick that already has its partitions). **Not yet boot-tested**: boot
      it from the firmware menu, check Wi-Fi (`nmtui`), the internal disk
      (UFS) and a backup onto its `BOOK4-BACKUP` partition. **8 Oct: first
      boot stopped at a bare `grub>` prompt** (built-in config failed:
      search for /book4-rescue.id or configfile /book4/grub.cfg). Check the
      stick with `install/arch/rescue-usb-check.sh`. Cause: the built-in
      config was missing from BOOTAA64.EFI (written to the stick's /tmp,
      which systemd-nspawn hides behind a tmpfs). Fixed in the script; on an
      existing stick: `GRUB_ONLY=1 bash install/arch/rescue-usb.sh /dev/sdX`. **After
      the GRUB rebuild the stick boots, with Wi-Fi** (8 Oct). Left: a
      backup onto `BOOK4-BACKUP` and the sshd decision below. On this stick,
      once: `sudo systemctl disable --now systemd-networkd systemd-networkd.socket`
      (the Arch Linux ARM base enables it next to NetworkManager; fixed in the
      script). No restore script yet: each backup writes `RESTORE.md` with the
      manual steps.
      sshd (enabled by the Arch Linux ARM base, password login, no
      firewall): the script now disables it; on the stick built 6 Oct, once:
      `sudo systemctl disable --now sshd` (start it by hand when needed).
- [ ] **`install/arch/fedora-shell.sh`**: works (6 Oct): read-only command,
      running Fedora's tools in the container, redirected output (`--pipe`);
      used to build and publish the kernel branch. Not yet run:
      `--sync-modules` + reboot.
- [ ] **Omarchy Dragon**: offer the working 14" and test cycles to the
      official effort (`omacom/omarchy#8672`); nobody there owns a Samsung.
      Plan in [omarchy.md](omarchy.md).

## Repository

- [ ] Device tree **sources**: only the camera DTS (`dts/src/`) and the
      patches sent to Anatase (`dts/patches/`) are here. The compiled
      `dts/*.anatase.dtb` (1 Oct, `ene,kb9058-battery` compatible) is what the
      **Fedora fallback kernel** boots with the DKMS drivers in
      `drivers/anatase/` (`ene-kb9058-battery.c`, `samsung-emuec.c`); keep the
      three in step. The Anatase kernel uses the DTB built with it.

## Done

- Boot, display/GPU, keyboard and backlight, touchpad, touchscreen, Wi-Fi,
  Bluetooth, battery and charging (incl. hot replug, `patches/0001`), USB-C,
  speakers and microphones, suspend/resume, EFI variables, RTC, Windows from
  GRUB, GRUB update guard (1-2 Oct).
- Anatase kernel built locally and default (1 Oct); camera with privacy LED
  as default DTB (2 Oct, `/etc/book4/default-dtb`).
- Full `dnf update` with kernel and firmware held back (1 Oct).
- **Charger unplugged during sleep reset the machine**: fixed 4 Oct by
  `drivers/anatase/patches/0002` (quiesce `samsung-emuec` across sleep);
  tested on both ports, lid-close and direct s2idle, plug-in during sleep.
- Boot hook prefers the DTB built with each kernel; falls back to
  `/usr/lib/firmware/book4/` (Fedora kernel).
- Arch Linux ARM in a second btrfs subvolume with Omarchy 4.0.4 (2-3 Oct).
- Licence (GPL-2.0-only code, CC BY 4.0 docs); repository public and shared
  (zensanp/linux-book4-edge #3 #4 #8, ciscobugger/book4-edge-linux#3, Fedora
  Discussion) (1-2 Oct).
- Superseded: our own keyboard backlight driver (`0x62`; Anatase's mailbox
  driver does it), the EC event queue (in Anatase's DTS), the experimental
  sleep patches v1/v2 and the EC display-bit test (`patches-experimental/`).

- **CPU capacity with boost** (23 October): all CPUs report `cpu_capacity`
  1024, so single-threaded work also lands on cluster 0 (3.42 GHz) instead of
  the 4.0 GHz clusters. Geekbench single-core 2200 unpinned, 2482 pinned to
  CPUs 4-11. Cause: no `capacity-dmips-mhz` in hamoa.dtsi, so no capacities
  at all. sleep-backport 0038 adds it: verified 23 October, capacities
  872/1024/1024, 10 of 10 unpinned busy loops on CPUs 4-11, a busy task
  released from CPU 1 moves there within 1 s (misfit migration). The three
  clusters have identical energy models, so EAS has nothing to choose by.
  Open: an unpinned Geekbench single-core run (expect ~2480).
