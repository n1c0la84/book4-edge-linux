# Open points

State on 4 October 2026 (14" NP940XMA; Fedora 45 and Arch Linux ARM with
Omarchy, both on the Anatase kernel `7.2.7-book4`). Roughly in order of
everyday usefulness within each section. What is already done is listed at
the end.

**Next for the Linux side (8 October):** the tests collected in Windows,
in order: [handoff-linux-from-windows.md](handoff-linux-from-windows.md).

## To test (should work, never verified)

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
- [ ] **Suspend drain is about 1.7 W** (~6 %/h, ~16 h from full) on both
      kernels and desktops. The SoC does not seem to power-collapse on
      Linux; **under Windows it does** (sleep study, 8 Oct: hardware low
      power ~98 % of each sleep), so the hardware can.
      [power.md](power.md).
- [ ] **Hibernation** as a workaround for the drain. Both kernels have
      `CONFIG_HIBERNATION=y`, lockdown is off. Needs a ~20 GB btrfs swap file
      (current swap is zram), `resume=` + `resume_offset=` in the boot hook's
      command line, and the resume module in the initramfs. Unknown: whether
      ADSP/CDSP, GPU and ath12k survive a restore on X1E. The RTC cannot wake
      this machine, but the EC has a wake timer (`EC2.sys`
      `IOCTL_START_WAKEUP`, see [power.md](power.md)) that could make
      suspend-then-hibernate possible. Command decoded (8 Oct,
      [ec-protocol.md](ec-protocol.md#wake-timer-raw-target-0x62-decoded-8-october-2026)):
      `{03, T/60, T%60}` on 0x62, T 0-255 in an unknown unit. Next, on
      Linux: `sudo python3 tools/ec/wake-timer.py once 90 --sleep` to find
      the unit and whether the EC can wake the machine from s2idle.
      EC wake timer tested 8 Oct: no wake and no EC interrupt (see
      [ec-protocol.md](ec-protocol.md#wake-timer-raw-target-0x62-decoded-8-october-2026)); parked.
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
- [ ] **Fingerprint reader** (8 Oct): hardware works with `usb_2` enabled
      ([dts/patches/0004](../dts/patches), the "alt DT fingerprint.dtb"
      entry): EgisTec `1c7a:05a1` (ETU905A80-E, firmware 9050.1.2.32)
      enumerates, fprintd enrolls (USB autosuspend off:
      `userspace/fingerprint/`). But the sensor does not keep the print:
      verify finds 0 prints on the chip and fprintd deletes the enrolment.
      Known egismoc issue: this firmware stores prints only over SDCP, which
      Fedora's libfprint 1.94.100 lacks; fixed by libfprint MR !547 (SDCP v2,
      unmerged, head `2d7c5277`), confirmed on a Galaxy Book4 Pro with the
      same sensor (lanlanndn/galaxybook4-fingerprint). A Fedora spec for it
      is prepared in `~/src/fp-rpm` (not built). Decide: build MR !547, or
      wait for it to land in a release.
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

- [ ] **Make the Arch/Omarchy setup reproducible end to end**: stage 1-2 and
      the Omarchy stage 3 scripts exist in `install/arch/`, but
      `stage3-omarchy-install.sh` as a whole has not been run. [arch.md](arch.md).
- [ ] **Rescue USB stick** (`install/arch/rescue-usb.sh`): a generic live
      USB cannot boot this machine (no `cutmem`, no device tree, no Anatase
      drivers). **Built 6 Oct** on a 64 GB stick (first run stopped at an
      expired sudo prompt; the script now keeps sudo alive and resumes on a
      stick that already has its partitions). **Not yet boot-tested**: boot
      it from the firmware menu, check Wi-Fi (`nmtui`), the internal disk
      (UFS) and a backup onto its `BOOK4-BACKUP` partition. On this stick,
      once: `sudo systemctl disable --now systemd-networkd systemd-networkd.socket`
      (the Arch Linux ARM base enables it next to NetworkManager; fixed in the
      script). No restore script yet: each backup writes `RESTORE.md` with the
      manual steps.
      **sshd is enabled on the stick** (Arch Linux ARM base) with password
      login and no firewall: decide off by default or home-subnet only as on
      the installed Arch (`install/arch/ssh-lan.sh`), and fix the script.
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
