# Open points

State on 20 October 2026 (14" NP940XMA): Arch Linux ARM with Omarchy, daily
at EL2 on the sleep kernel `7.2.7-book4s` with full s2idle deep sleep;
Fedora next to it as the build host. Roughly in order of everyday usefulness
within each section. What is already done is listed at the end.

**Now (20 October):**

- [ ] **Live stick, then an installer** (29 October): boot-test
      `install/arch/live-image.sh` (EL1 and EL2 entries). Next: an installer
      on the stick that copies its system to sda5 as a new subvolume (old
      `arch` kept) with its own boot chain on the internal ESP (no Fedora
      GRUB), dry-run first; later a public variant without tcblaunch.exe and
      firmware (extracted from the Windows partition at first boot).
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
- [ ] **Move to 7.3** once Anatase has a 7.3 tree: most of
      `tools/kernel/sleep-backport/` is in 7.3 already.
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
      (`install/el2/sleep-setup.sh`). At EL1 under Gunyah it still never
      collapses. The rest of the board's power is under "Now" above;
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
- [ ] `deep` suspend never resumes (s2idle works; probably leave it).
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
