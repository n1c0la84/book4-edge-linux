# Open points

State on 4 October 2026 (14" NP940XMA; Fedora 45 and Arch Linux ARM with
Omarchy, both on the Anatase kernel `7.2.7-book4`). Roughly in order of
everyday usefulness within each section. What is already done is listed at
the end.

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
      and HDMI (`rtd2171` bridge, `simple_bridge`). Also the last open check
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
      Hyprland on the Anatase kernel); what its two "UNKNOWN" HID interfaces
      are (pen? gestures?).

## Open problems

- [ ] **CPU boost** (`/sys/devices/system/cpu/cpufreq/boost` = 0): try 4 GHz
      single/dual-core boost; watch temperature and battery.

- [ ] **Suspend drain is about 1.7 W** (~6 %/h, ~16 h from full) on both
      kernels and desktops. The SoC does not seem to power-collapse.
      [power.md](power.md).
- [ ] **Hibernation** as a workaround for the drain. Both kernels have
      `CONFIG_HIBERNATION=y`, lockdown is off. Needs a ~20 GB btrfs swap file
      (current swap is zram), `resume=` + `resume_offset=` in the boot hook's
      command line, and the resume module in the initramfs. Unknown: whether
      ADSP/CDSP, GPU and ath12k survive a restore on X1E. The RTC cannot wake
      this machine, but the EC has a wake timer (`EC2.sys`
      `IOCTL_START_WAKEUP`, see [power.md](power.md)) that could make
      suspend-then-hibernate possible.
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
- [ ] **Fingerprint reader**: not visible to Linux at all.
- [ ] **CDSP channels fail at boot** on every boot, both kernels, Fedora and
      Arch: `fastrpc` / `qcom_smd_qrtr` on `32300000.remoteproc` "failed to
      create endpoint" (-12), together with a `qcom-apm` "CMD timeout". No
      visible effect so far. Details in [arch.md](arch.md).
- [ ] **GPIO 44 (MODS)**: the firmware's Modern Standby "display off/on"
      signal to the EC, reserved in the DTS. Not needed for the unplug fix,
      but it changes how the EC handles power events in sleep; worth
      revisiting together with the drain. [power.md](power.md).
- [ ] `deep` suspend never resumes (s2idle works; probably leave it).
- [ ] EC word at `0xb6` (37 on this unit): cycle-count candidate, watch
      whether it ever increments.

## Upstream

Details in [upstream.md](upstream.md).

Waiting for a reply (Anatase, `anatase-org/kernel-anatase`):

- [ ] #1 PD request retry after hot plug (+ cycle-count register note).
- [ ] #2 Front camera and privacy LED, device tree.
- [ ] #3 Machine reset when the charger is unplugged during sleep.

Not yet reported:

- [ ] ath12k / linux-firmware: WCN7850 firmware c7-00108 regression on this card.
- [ ] systemd/libinput: keyboard tagged as tablet pad.
- [ ] Saddytech driver: design/last-full swapped, rate sign.
- [ ] linux-arm-msm DTS thread: `pmic-glink` cannot work with this firmware
      image (and, if wanted, a tester's report on the v6 series).
- [ ] Help get `samsung-galaxybook-ec` and `samsung-emuec` to mainline, even
      only as a tester. Until they land, every distribution needs a patched
      kernel for this laptop.

## Arch and Omarchy

- [ ] **Make the Arch/Omarchy setup reproducible end to end**: stage 1-2 and
      the Omarchy stage 3 scripts exist in `install/arch/`, but
      `stage3-omarchy-install.sh` as a whole has not been run. [arch.md](arch.md).
- [ ] **Rescue USB stick** (`install/arch/rescue-usb.sh`, written 5 Oct,
      **untested**): a generic live USB cannot boot this machine (no
      `cutmem`, no device tree, no Anatase drivers). Build it on the 64 GB
      stick, boot it from the firmware menu, check Wi-Fi, the internal disk
      (UFS) and a backup onto its `BOOK4-BACKUP` partition.
- [ ] **`install/arch/fedora-shell.sh`** (Fedora container from Arch, incl.
      `--sync-modules`): written 5 Oct, not yet run. Test in three steps
      (read-only command, interactive shell, `--sync-modules` + reboot).
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
