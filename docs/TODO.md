# Open points

State on 1 October 2026 (14" NP940XMA, Fedora 45, kernel 7.2.0-61). Roughly in
order of everyday usefulness within each section.

## To test (should work, never verified)

- [ ] **Full `dnf update`** (963 packages pending, incl. kernel 7.2.8,
      linux-firmware, systemd, PipeWire, Mesa). Follow [updates.md](updates.md);
      check `cutmem` in the ESP grub.cfg before rebooting.
- [ ] **Kernel 7.2.8** from the "(other)" menu entry after the update: DKMS
      modules built, display/battery/Wi-Fi/audio fine; then pin it
      (`/etc/book4/default-kernel`).
- [ ] **External monitor**: USB-C DisplayPort (DP alt-mode via `samsung-emuec`)
      and HDMI (`rtd2171` bridge, `simple_bridge`).
- [ ] **Headphones and headset microphone** (UCM devices exist, jack untested).
- [ ] **Battery drain in suspend** overnight (s2idle may not reach the deepest
      state on X1E).
- [ ] **GRUB guard on a future GRUB update**, including the `chain.mod` copy for
      the Windows entry (the guard was tested before the Windows entry existed).
- [ ] **`install/install-fedora.sh` end to end** on a fresh install (each step
      was tested on its own, the script as a whole never).
- [ ] Wi-Fi after a `linux-firmware`/`atheros-firmware` update: a new
      `board-2.bin` could change which board data ath12k uses.

## Not working (needs investigation)

- [ ] **Keyboard backlight**: command known, driver blinks. Ideas in
      [keyboard-backlight.md](keyboard-backlight.md).
- [ ] **Touchscreen**: Goodix `27C6:0123` binds via `i2c_hid_of` as a mouse plus
      two "UNKNOWN" interfaces; no touch input.
- [ ] **Webcam**: no device tree node in any tree yet.
- [ ] **Fingerprint reader**: not visible to Linux at all.
- [ ] **EFI variables / NVRAM boot entries and the RTC** (clock resets each
      boot): need the QSEECOM allowlist patch (Anatase has it), i.e. a kernel
      build.
- [ ] **Possibly four speakers**: each speaker bus also enumerates a second
      WSA883x at SoundWire address 1 that no device tree describes
      ([audio.md](audio.md)).
- [ ] **EC event queue** (0x62, plain 12-byte reads; hotkey, fan and ACPI
      events per EC2.sys) is never drained by Linux. Nothing visibly depends
      on it now, but hotkeys and the keyboard backlight might.
- [ ] `deep` suspend never resumes (s2idle works; probably leave it).
- [ ] EC word at `0xb6` (37 on this unit): cycle-count candidate, watch whether
      it ever increments.

## To report upstream

Details in [upstream.md](upstream.md):

- [ ] Anatase: PD request retry after hot plug (patch ready), cycle count
      register (`0xd0` is the state of charge here).
- [ ] Saddytech driver: design/last-full swapped, rate sign.
- [ ] ath12k / linux-firmware: WCN7850 firmware c7-00108 regression on this card.
- [ ] systemd/libinput: keyboard tagged as tablet pad.
- [ ] linux-arm-msm DTS thread: `pmic-glink` cannot work on this machine (and,
      if wanted, a tester's report on the v6 series).

## Repository

- [ ] Choose a licence for our own files (drivers are GPL-2.0-only, the UCM
      profile BSD-3-Clause; scripts and docs have none yet).
- [ ] Review [CREDITS.md](../CREDITS.md) before making the repository public.
- [ ] Import the device tree **sources** (only compiled DTBs are here; the
      sources are on the workstation / in Anatase's tree).
- [ ] Try another distribution (the repo is Fedora-only so far).
