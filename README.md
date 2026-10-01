# Linux on the Samsung Galaxy Book4 Edge (14", Snapdragon X Elite)

Working notes, configuration and drivers for running a mainline-based Linux
distribution on the **Samsung Galaxy Book4 Edge 14" (NP940XMA, X1E80100)**.
**Currently Fedora only:** everything here was developed and tested on
Fedora 45 (aarch64, kernel 7.2.0-61). The pieces are written so they can be
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
| Keyboard backlight | experimental, disabled | can be switched on (EC command `{0x10, x, level}` at 0x62) but our driver can't keep it lit without blinking: [docs/keyboard-backlight.md](docs/keyboard-backlight.md) |
| Touchpad | works | stock |
| Wi-Fi (WCN7850) | works | specific firmware, [docs/firmware.md](docs/firmware.md) |
| Bluetooth | works | controller needs a public address: [userspace/bluetooth](userspace/bluetooth) |
| Battery / AC | works | Anatase `ene-kb9058-battery` |
| USB-C data, hot-plug | works | Anatase `samsung-emuec` |
| Charging, incl. hot replug at 20 V | works | `samsung-emuec` + [our retry patch](drivers/anatase/patches) |
| Speakers (stereo) | works | topology alias + UCM profile: [docs/audio.md](docs/audio.md) |
| Internal microphones | works | DMIC0/1, gain raised in the UCM profile |
| Headphones, headset mic | profile present, untested | |
| Suspend (s2idle): lid close/open, power key | works | `mem_sleep_default=s2idle`; both lid and power key suspend and wake; overnight drain not measured |
| `deep` suspend | never resumes | do not use |
| External monitor (USB-C DisplayPort, HDMI) | not tested yet | DT and `samsung-emuec` support DP alt-mode; HDMI goes through an `rtd2171` bridge (`simple_bridge`) |
| Touchscreen | does not work | Goodix `27C6:0123` binds via `i2c_hid_of` but only as a mouse + two "UNKNOWN" interfaces; no touch input |
| Webcam | does not work | no device tree node in any tree yet |
| Fingerprint reader | does not work | not visible to Linux at all (no USB/SPI device; `fprintd`: no devices); not investigated |
| EFI variables / NVRAM boot entries | not working | needs the QSEECOM allowlist patch (Anatase has it, needs a kernel build) |
| RTC | resets to a fixed date each boot | probably also QSEECOM |

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

    docs/         how it works and how we got here
    firmware/     what to extract from Windows (no blobs are shipped)
    dts/          the device trees we boot (compiled, with provenance)
    drivers/
      anatase/    Anatase's battery + Type-C drivers, pristine, plus our patches (DKMS)
      book4-ec/   our own EC battery driver - superseded, kept as a record
      book4-kbd-backlight/  keyboard backlight driver - experimental, disabled
    userspace/    boot hook, udev/modprobe/dracut snippets, Bluetooth, audio
    tools/        EC test tool, disassembly annotator, Windows registry helper
    install/      install-fedora.sh

## Installing (Fedora)

On a system that already boots this machine:

    bash install/install-fedora.sh [BLUETOOTH_ADDRESS]

Read the script first: it is assembled from individually tested steps but has
not been run end to end on a fresh system.

## Credits

Much of what works here is other people's work, above all the
[Anatase](https://github.com/anatase-org/patchwork) project (Antheas
Kapenekakis), Maxim Storetvedt's DTS series, Linaro's X1E80100 audio work
and the linux-firmware/Debian packagers. **[CREDITS.md](CREDITS.md) lists every
file taken from elsewhere with its origin, author, licence and whether we
changed it**, and separates that from our own work.

Copied files keep their original copyright and licence headers. Drivers are
GPL-2.0-only as marked; the UCM profile is BSD-3-Clause (derived from
alsa-ucm-conf).
