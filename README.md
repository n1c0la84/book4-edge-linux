# Linux on the Samsung Galaxy Book4 Edge (14", Snapdragon X Elite)

Working notes, configuration and drivers for running a mainline-based Linux
distribution on the **Samsung Galaxy Book4 Edge 14" (NP940XMA, X1E80100)**.
Developed on Fedora 45 (kernel 7.2.0-61); written so the pieces can be carried
to other distributions.

This builds on the **[Anatase](https://github.com/anatase-org/patchwork)**
project (branch `anatase-7.2`), whose device tree and EC/Type-C drivers we use,
and adds what we found and fixed independently.

## Status (1 October 2026, 14" model)

| Area | State | How |
|---|---|---|
| Boot from internal UFS | works | hand-built DTB via GRUB `devicetree`, `cutmem`, see [docs/bootstrap.md](docs/bootstrap.md) |
| Display (eDP) | works | needs `samsung-emuec` loaded (it provides the USB-C DP bridges) |
| Keyboard | works | udev rule: [userspace/keyboard](userspace/keyboard) |
| Touchpad | works | stock |
| Wi-Fi (WCN7850) | works | specific firmware, [docs/firmware.md](docs/firmware.md) |
| Bluetooth | works | controller needs a public address: [userspace/bluetooth](userspace/bluetooth) |
| Battery / AC | works | Anatase `ene-kb9058-battery` |
| USB-C data, hot-plug | works | Anatase `samsung-emuec` |
| Charging, incl. hot replug at 20 V | works | `samsung-emuec` + [our retry patch](drivers/anatase/patches) |
| Speakers (stereo) | works | topology alias + UCM profile: [docs/audio.md](docs/audio.md) |
| Headphones, microphones | profile present, untested | |
| Lid-close suspend (s2idle) | works | `mem_sleep_default=s2idle`; overnight drain not measured |
| `deep` suspend | never resumes | do not use |
| USB-C DisplayPort, HDMI | untested | |
| Webcam | not supported | no DT node anywhere yet |
| EFI variables / NVRAM boot entries | not working | needs the QSEECOM allowlist patch (Anatase has it, needs a kernel build) |
| RTC | resets to a fixed date each boot | probably also QSEECOM |

## Layout

    docs/         how it works and how we got here
    firmware/     what to extract from Windows (no blobs are shipped)
    dts/          the device trees we boot (compiled, with provenance)
    drivers/
      anatase/    Anatase's battery + Type-C drivers, pristine, plus our patches (DKMS)
      book4-ec/   our own EC battery driver - superseded, kept as a record
    userspace/    boot hook, udev/modprobe/dracut snippets, Bluetooth, audio
    tools/        EC test tool, disassembly annotator, Windows registry helper
    install/      install-fedora.sh

## Installing (Fedora)

On a system that already boots this machine:

    bash install/install-fedora.sh [BLUETOOTH_ADDRESS]

Read the script first: it is assembled from individually tested steps but has
not been run end to end on a fresh system.

## Credits

- Anatase / Antheas Kapenekakis: device tree corrections, `ene-kb9058-battery`,
  `samsung-emuec`, QSEECOM allowlist, keyboard HID quirk.
- Maxim Storetvedt: the original Galaxy Book4 Edge DTS series on linux-arm-msm.
- This repository: EC protocol reverse-engineered independently from the
  Windows driver (matching Anatase's), charger hot-plug PD retry, audio UCM
  profile, Bluetooth address service, boot hook, Wi-Fi firmware findings.

Drivers are GPL-2.0-only as marked in their headers.
