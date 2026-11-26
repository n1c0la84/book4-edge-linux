# Linux on the Samsung Galaxy Book4 Edge (14", Snapdragon X Elite)

Working notes, Arch packages, userspace services, configuration and kernel
patches for running Linux on the **Samsung Galaxy Book4 Edge 14" (NP940XMA,
X1E80100)**.

**How the reference machine runs (26 November 2026):** **Arch Linux ARM with
Omarchy 4.5** as the only Linux install (Fedora was retired and deleted on
23 November; Windows stays on `sda3`), booted **at EL2** (Linux as its own
hypervisor, no Qualcomm Gunyah) via **Limine + EL2 UKIs** on a second ESP
(`sda7`, `/boot`, with Arch GRUB on `sda4` as fallback). It runs our packaged
kernel `linux-book4` (`7.3.4-book4`, built natively on Arch from
[n1c0la84/linux-book4-edge](https://github.com/n1c0la84/linux-book4-edge)
branch `book4/7.3` on Anatase 7.3) plus the Book4 layer packages from the
signed online `[book4]` repository ([docs/packages-online.md](docs/packages-online.md)).

- **Current state & log:** [docs/STATE.md](docs/STATE.md)
- **Roadmap:** [docs/ROADMAP.md](docs/ROADMAP.md)
- **Set it up / online `[book4]` repository:** [docs/install.md](docs/install.md), [docs/packages-online.md](docs/packages-online.md)
- **Keep it updated:** [docs/updates.md](docs/updates.md)
- **Open points:** [docs/TODO.md](docs/TODO.md)

This builds on the **[Anatase](https://github.com/anatase-org/patchwork)**
project (7.3 kernel, device tree and Samsung EC/Type-C drivers), on
**[Omarchy](https://omarchy.org)**, on
**[justririll/x1e-sleep](https://github.com/justririll/x1e-sleep)** for deep
sleep, on **[rafaelmnz/SB4-Edge-Linux](https://github.com/rafaelmnz/SB4-Edge-Linux)**
for the ambient light sensor, fingerprint import and mic noise suppression, and
on Stephan Gerhold's `qebspil` and Nikita Travkin's `slbounce` for EL2
([CREDITS.md](CREDITS.md)).

## Status (26 November 2026, 14" model)

| Area | State | How |
|---|---|---|
| Boot from internal UFS | works | Limine + EL2 UKIs on second ESP `/boot` (`sda7`, no `cutmem` needed on 7.3/Limine), managed by `book4-edge-boot`; Arch GRUB on `sda4` as fallback ([docs/plan-limine.md](docs/plan-limine.md)) |
| Linux at EL2 (KVM, no Qualcomm hypervisor) | **works, default boot** | UEFI Shell + `qebspil` (starts ADSP/CDSP; Linux attaches) + `slbounce` -> Limine, packaged in `book4-edge-el2` ([docs/el2.md](docs/el2.md)) |
| Windows dual-boot | works | Windows kept on `sda3` (firmware F10 menu or `windows.nsh`); needed for firmware/BIOS updates and Windows Hello fingerprint enrolment |
| Display (eDP 2880×1800) | works | `samsung-emuec` provides the USB-C DP bridges; eDP backlight via `dp_aux_backlight` |
| Ambient light sensor & auto-brightness | **works (EL1 and EL2)** | VEML3328 via ADSP Qualcomm Sensor Core (`fastrpc`, `libssc-book4`, `iio-sensor-proxy-book4`, `book4-sensors`) + `book4-autobrightness` user service ([docs/sensors.md](docs/sensors.md)) |
| Keyboard & Copilot key | works | udev rule ([userspace/keyboard](userspace/keyboard)); optional `keyd` remaps Copilot to Super |
| Fn keys & keyboard backlight | works | stock HID + `samsung-galaxybook-ec` (`0xFF10` mailbox) |
| Touchpad & touchscreen | works | stock `i2c_hid_of` (Goodix `27C6:0123` multitouch) |
| Wi-Fi (WCN7850) & Bluetooth | works | `c5-00302` Wi-Fi firmware ([docs/firmware.md](docs/firmware.md)); Bluetooth public-address service ([userspace/bluetooth](userspace/bluetooth)) |
| Battery, AC & USB-C charging | works (incl. hot replug at 20 V) | `samsung-galaxybook-ec` + `samsung-emuec` in `linux-book4` (PD retry, sleep quiesce, wake on plug-in, EC input-limit handover); awake drain logger `book4-drain` |
| Speakers, all four (2 woofers + 2 tweeters) | works (sporadic SoundWire clash after resume) | 14" DT + UCM profile + PipeWire crossover/limiter (`book4-speakers.conf`), clock resync fix (`book4-clock.conf` + `rtkit`) ([docs/audio.md](docs/audio.md)); see [docs/TODO.md](docs/TODO.md) for SoundWire clashes |
| Internal microphones | works | DMIC0/1 + WebRTC noise suppression (`book4-mic-ns.conf`) |
| Headphones / headset mic | output profile present; headset mic open | see [docs/TODO.md](docs/TODO.md) |
| Suspend (`s2idle` at EL2; `s2idle` / `deep` at EL1) | **full SoC deep sleep** (~0.70 W at EL2, ~0.77–0.84 W at EL1; AOSD off) | `cxsd`/`ddr` ~98–100 % with both DSPs running; `book4-el2-sleep.service` + `aoss_cxsd_only` + `el1tmr` ([docs/power.md](docs/power.md)). Remaining ~0.6 W over Windows (0.11 W) is board power under investigation |
| Hardware video decoding (Iris) | partial | 1080p H.264/HEVC works at EL2 (non-TZ start); odd-size streams (e.g. 2832×1700) fault Iris until reboot; mpv uses `hwdec=auto-safe` |
| Webcam | works (browsers / PipeWire) | OV02C10 on CCI0 + CAMSS + libcamera software ISP (~40 fps, TLMM 110 privacy LED); Qt V4L2 apps still open ([docs/camera.md](docs/camera.md)) |
| Fingerprint reader | works | EgisTec `1c7a:05a1` on `usb_2`, `libfprint-sdcp` (MR !547), Windows enrolment import (`book4-fingerprint-import`), `book4-resume-check` health check |
| External monitor | HDMI works; USB-C DP open | HDMI via `rtd2171` bridge; USB-C DP hits AUX timeouts |
| NPU (Hexagon CDSP) | in progress | FastRPC works; `dspqueue` hangs on Samsung's `c1-00078` firmware (`dspsignal` ported, untested) |
| EFI variables & RTC | works (EL1 and EL2) | QSEECOM allowlist + Linux-owned SHM bridges at EL2 (`efibootmgr` and `rtc0` work) |
| Hibernation | broken | resume resets the machine; not used (zram swap only) |

## Layout

    packages/        Arch PKGBUILDs for the Book4 layer: linux-book4, book4-edge,
                     book4-edge-boot, book4-edge-el2, book4-edge-firmware (local only),
                     fastrpc, libssc-book4, iio-sensor-proxy-book4, book4-sensors,
                     libfprint-sdcp
    userspace/       services, udev/modprobe/mkinitcpio snippets, audio (UCM/PipeWire),
                     sensors & auto-brightness, boot/Limine hooks, EL2 helpers, standby
                     hooks, drain logger, update helper
    .github/         GitHub Actions: signed [book4] package builder (packages.yml)
                     and syntax/unit/DTB lint checks (lint.yml)
    keys/            GPG public keys (book4-repo.asc, archlinuxarm-build-system.asc)
    dts/             active EL2 overlay (dts/src/x1-el2-book4.dtso) + 7.2-era DT archive
    install/         Arch setup/migration/firmware-staging scripts (install/arch/),
                     EL2 patches (install/el2/), plus retired Fedora scripts
    tools/           power/sleep diagnostics & out-of-tree sleep modules (tools/power/),
                     backup & snapshot scripts (tools/backup/), kernel/audio/video/EC/NPU
                     tools, and historical experiments (tools/experiments/)
    drivers/         7.2-era DKMS drivers & patches (superseded by linux-book4 7.3)
    docs/            architecture, power, audio, sensors, packaging, state & upstream drafts
    LICENSES/        full licence texts (see LICENSE)

## Credits & Licence

Much of what works here builds on other people's work; **[CREDITS.md](CREDITS.md)**
lists third-party origins, authors and licences. Our own code, scripts and
packaging recipes are **GPL-2.0-only**, and our documentation is **CC BY 4.0**
([LICENSE](LICENSE)).
