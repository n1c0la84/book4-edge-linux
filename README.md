# Linux on the Samsung Galaxy Book4 Edge (14", Snapdragon X Elite)

Working notes, configuration and drivers for running a mainline-based Linux
distribution on the **Samsung Galaxy Book4 Edge 14" (NP940XMA, X1E80100)**.
**Currently Fedora only:** everything here was developed and tested on
Fedora 45 (aarch64). Since 1 October it runs a kernel built from Anatase's
`anatase-7.2` tree (7.2.7 plus our charger patch, see [docs/kernel.md](docs/kernel.md));
it is the **default** boot entry, and the stock Fedora kernel 7.2.0-61 with the
DKMS drivers stays in the menu as the fallback ("(other)"). The pieces are written so they can be
carried to other distributions, but no other distribution has been tried yet.

This builds on the **[Anatase](https://github.com/anatase-org/patchwork)**
project (branch `anatase-7.2`), whose device tree and EC/Type-C drivers we use,
and adds what we found and fixed independently.

## Status (1 October 2026, 14" model)

| Area | State | How |
|---|---|---|
| Boot from internal UFS | works | hand-built DTB via GRUB `devicetree`, `cutmem`, see [docs/bootstrap.md](docs/bootstrap.md) |
| Windows from the GRUB menu | works | Fedora's signed arm64 GRUB has no built-in `chainloader`; the hook copies `chain.mod` to `\EFI\book4\arm64-efi\` and the entry loads it |
| Display (eDP) | works | needs `samsung-emuec` loaded (it provides the USB-C DP bridges) |
| Keyboard | works | udev rule: [userspace/keyboard](userspace/keyboard) |
| Fn keys: brightness, volume | work | stock HID |
| Keyboard backlight | works (Anatase kernel) | Anatase's `samsung-galaxybook-ec` drives it via the `0xFF10` mailbox and handles the hotkey; our own `0x62` experiment blinks and is superseded ([docs/related-work.md](docs/related-work.md)) |
| Touchpad | works | stock |
| Wi-Fi (WCN7850) | works | specific firmware, [docs/firmware.md](docs/firmware.md) |
| Bluetooth | works | controller needs a public address: [userspace/bluetooth](userspace/bluetooth) |
| Battery / AC | works, incl. charging confirmed | Anatase `samsung-galaxybook-ec` (built into the Anatase kernel); `ene-kb9058-battery` via DKMS on the Fedora kernel |
| USB-C data, hot-plug | works | Anatase `samsung-emuec` |
| Charging, incl. hot replug at 20 V | works | `samsung-emuec` + [our retry patch](drivers/anatase/patches) |
| Speakers (stereo) | works | topology alias + UCM profile: [docs/audio.md](docs/audio.md) |
| Internal microphones | works | DMIC0/1, gain raised in the UCM profile |
| Headphones, headset mic | profile present, untested | |
| Suspend (s2idle): lid close/open, power key | works | `mem_sleep_default=s2idle`; both lid and power key suspend and wake; drain measured at 1 % in 3 h 04 min (about 0.2 W) |
| `deep` suspend | never resumes | do not use |
| External monitor (USB-C DisplayPort, HDMI) | not tested yet | DT and `samsung-emuec` support DP alt-mode; HDMI goes through an `rtd2171` bridge (`simple_bridge`) |
| Touchscreen | does not work | Goodix `27C6:0123` binds via `i2c_hid_of` but only as a mouse + two "UNKNOWN" interfaces; no touch input |
| Webcam | does not work | sensor identified (OV02C10, I2C 0x36), no device tree node yet: [docs/camera.md](docs/camera.md) |
| Fingerprint reader | does not work | not visible to Linux at all (no USB/SPI device; `fprintd`: no devices); not investigated |
| EFI variables / NVRAM boot entries | works (Anatase kernel) | QSEECOM allowlist; 197 variables, `efibootmgr` reads the boot order; not working on the Fedora kernel |
| RTC | set (Anatase kernel), persistence across reboot to be verified | UTC: `hwclock --systohc --utc` wrote it (offset kept in the `RTCInfo` EFI variable); Windows needs `RealTimeIsUniversal=1`, see [docs/kernel.md](docs/kernel.md) |

**Open points** (to test, not working, to report): [docs/TODO.md](docs/TODO.md).

**Who else is working on this machine**, what they already have and what is
genuinely ours: [docs/related-work.md](docs/related-work.md).
**Carrying this to Arch / Omarchy Dragon**, where nobody owns a Samsung:
[docs/omarchy.md](docs/omarchy.md).
**The Anatase kernel**: why it is worth running, how it is built and installed,
and what it fixed here: [docs/kernel.md](docs/kernel.md).

## Updating the system

**Read [docs/updates.md](docs/updates.md) before `dnf update`.** A GRUB package
update overwrites the boot configuration this machine needs; `install/guard-grub.sh`
makes that safe.

What has actually been done so far (1 October 2026):

- **GRUB only:** `grub2*` upgraded from 2.12-76 to 2.12-81 with the guard in
  place. The guard restored `grub.cfg` (`cutmem` and `devicetree` present) and
  the machine booted normally afterwards.
- **A full `dnf update` has not been attempted yet** (963 pending packages,
  including kernel 7.2.8, linux-firmware, systemd, PipeWire and Mesa). The
  analysis in docs/updates.md says it should be safe; it is unverified.

## Layout

    docs/         how it works, how we got here, and who else is working on it
    (firmware)    nothing shipped: docs/firmware.md says what to extract from Windows
    dts/          the device trees we boot (compiled, with provenance)
    drivers/
      anatase/    Anatase's battery + Type-C drivers, pristine, plus our patches (DKMS)
      book4-ec/   our own EC battery driver - superseded, kept as a record
      book4-kbd-backlight/  keyboard backlight driver - experimental, disabled
    userspace/    boot hook, udev/modprobe/dracut snippets, Bluetooth, audio
    tools/        EC test tool, disassembly annotator, Windows registry helper
    install/      install-fedora.sh, install-anatase-kernel.sh, guard-grub.sh, helpers
    LICENSES/     full licence texts (see LICENSE)

## Installing (Fedora)

This is how the reference machine is set up. Every step was tested on it; the
scripts as a whole have not been run on a fresh install, so read them first.

0. **A system that boots** this machine: [docs/bootstrap.md](docs/bootstrap.md),
   and the DSP firmware copied from Windows: [docs/firmware.md](docs/firmware.md).
1. **Base layer and fallback kernel**:

       bash install/install-fedora.sh [BLUETOOTH_ADDRESS]

   Installs the boot hook, the keyboard/dracut/modprobe snippets, the audio
   profile, the Bluetooth address service and `mem_sleep_default=s2idle`, plus
   Anatase's drivers via DKMS and their device tree for the **stock Fedora
   kernel**. That alone gives a working laptop (battery, USB-C, charging,
   audio), minus the keyboard backlight, EFI variables and the clock.
2. **Recommended: the Anatase kernel** (adds the keyboard backlight, EFI
   variables, the clock, and keeps kernel, drivers and device tree in step).
   Build it as in [docs/kernel.md](docs/kernel.md) (about 25 minutes on the
   laptop), then:

       bash install/install-anatase-kernel.sh

   It is added to the GRUB menu next to the Fedora kernel; once tested, make
   it the default with `echo <version> | sudo tee /etc/book4/default-kernel`
   and re-run the boot hook.
3. **Before any `dnf update`**: `bash install/guard-grub.sh` once, and read
   [docs/updates.md](docs/updates.md).

Smaller helpers: `install/update-boot-hook.sh` and `install/update-audio.sh`
reinstall those pieces from the repo; `install/install-kbd-backlight.sh` and
`install/disable-kbd-backlight.sh` belong to our experimental keyboard
backlight driver, which the Anatase kernel makes unnecessary.

## Credits

Much of what works here is other people's work, above all the
[Anatase](https://github.com/anatase-org/patchwork) project (Antheas
Kapenekakis), Maxim Storetvedt's DTS series, Linaro's X1E80100 audio work
and the linux-firmware/Debian packagers. **[CREDITS.md](CREDITS.md) lists every
file taken from elsewhere with its origin, author, licence and whether we
changed it**, and separates that from our own work.

## Licence

Our code and scripts are **GPL-2.0-only**, our documentation **CC BY 4.0**;
files taken from others keep their own licences and copyright headers
(Anatase's drivers GPL-2.0-only, the UCM profile BSD-3-Clause from
alsa-ucm-conf). Details in [LICENSE](LICENSE) and [CREDITS.md](CREDITS.md).
