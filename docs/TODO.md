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
      [keyboard-backlight.md](keyboard-backlight.md). **Lead:** ciscobugger's
      `EC2.sys` command descriptor table (payload lengths per command) may
      explain the blinking. Note their table covers only commands `>= 0x80`,
      while ours is `0x10` at address `0x62` — the dispatcher branches elsewhere
      below `0x80` and nobody has followed it. This is still the most clearly
      new thing we have.
- [ ] **Touchscreen**: Goodix `27C6:0123` binds via `i2c_hid_of` as a mouse plus
      two "UNKNOWN" interfaces; no touch input.
- [ ] **Webcam**: no device tree node in any tree yet. **Lead:** ciscobugger has
      the camera working on the 15.6" with an **OV02C10** sensor (in-tree driver
      + DT node + an HFLIP patch for the 180-degree mounting). Our DSDT names
      only the Qualcomm CAMSS/CCI blocks (`QCOM0C06`, `QCOM0C26`, `QCOM0C32`) —
      `CAMP`, `CAMS`, `CAMF`, `CAMI`, `CAMT`, `CAMU` — and not the sensor, so
      identify it from the Windows driver store, the method that has worked
      every other time. If it is also an OV02C10, their DT node is most of it.
- [ ] **Fingerprint reader**: not visible to Linux at all.
- [ ] **EFI variables / NVRAM boot entries and the RTC** (clock resets each
      boot): one cause, the missing QSEECOM allowlist entry. The RTC dependency
      is not a guess — the DT node carries `qcom,uefi-rtc-info`, so the clock
      offset is stored in an EFI variable. Decision and method in
      [kernel.md](kernel.md): **do not rebuild, use Anatase's kernel RPMs**, but
      send them our PD retry patch first or it is lost. The UFS quirk is
      cosmetic and the HID keyboard quirk is marginal; neither justifies
      anything on its own.
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

- [ ] **Talk to ciscobugger** (15.6" NP750XQA) — highest value per minute of
      anything on this list; complementary gaps both ways. See
      [related-work.md](related-work.md) and the last section of
      [upstream.md](upstream.md).
- [ ] Anatase: PD request retry after hot plug (patch ready — note they are not
      the first to find it), cycle count register (`0xd0` is the state of charge
      here), and `CAPACITY` which could come from the gauge's own `0xa0`.
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
- [ ] Try another distribution (the repo is Fedora-only so far). The hardware
      layer (`dts/`, `firmware/`, `userspace/audio`, `userspace/keyboard`,
      `userspace/modprobe`) is already distribution-neutral; only the glue
      (`userspace/dnf`, `userspace/dracut`, `userspace/boot`, `install/`) is
      Fedora. An `install/install-omarchy.sh` beside the Fedora one is the
      shape. Omarchy Dragon has nobody on a Samsung — see
      [related-work.md](related-work.md).
