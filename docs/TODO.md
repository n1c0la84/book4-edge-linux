# Open points

State on 1 October 2026 (14" NP940XMA, Fedora 45, kernel 7.2.0-61). Roughly in
order of everyday usefulness within each section.

## To test (should work, never verified)

- [x] **Full `dnf update`** done 1 Oct with `kernel*` and `*firmware*` excluded (rebooted fine afterwards). Was: (963 packages pending, incl. kernel 7.2.8,
      linux-firmware, systemd, PipeWire, Mesa). Follow [updates.md](updates.md);
      check `cutmem` in the ESP grub.cfg before rebooting.
- [ ] **Kernel 7.2.8** from the "(other)" menu entry after the update: DKMS
      modules built, display/battery/Wi-Fi/audio fine; then pin it
      (`/etc/book4/default-kernel`).
- [ ] **External monitor**: USB-C DisplayPort (DP alt-mode via `samsung-emuec`)
      and HDMI (`rtd2171` bridge, `simple_bridge`).
- [ ] **Headphones and headset microphone** (UCM devices exist, jack untested).
- [ ] **Suspend drain is about 1.7 W** (~6 %/h) on both kernels and both
      desktops; the 1 October "0.2 W" was a misreading. Find what keeps the
      SoC from power-collapsing: [power.md](power.md).
- [ ] **Hibernation** as a workaround for the suspend drain. Both kernels have
      `CONFIG_HIBERNATION=y`, lockdown is off. Needs a ~20 GB btrfs swap file
      (current swap is zram), `resume=` + `resume_offset=` in the boot hook's
      command line, and dracut's resume module. Unknown: whether ADSP/CDSP,
      GPU and ath12k come back after restore on X1E. Suspend-then-hibernate
      may not work because the RTC cannot wake this machine; try plain
      hibernate first.
- [ ] **GRUB guard on a future GRUB update**, including the `chain.mod` copy for
      the Windows entry (the guard was tested before the Windows entry existed).
- [ ] **`install/install-fedora.sh` end to end** on a fresh install (each step
      was tested on its own, the script as a whole never).
- [ ] Wi-Fi after a `linux-firmware`/`atheros-firmware` update: a new
      `board-2.bin` could change which board data ath12k uses.

## Not working (needs investigation)

- [x] ~~**Keyboard backlight**~~ works on the Anatase kernel, hotkey too (1 Oct). — **solved upstream 30 Sept.** Anatase's new
      `samsung-galaxybook-ec` drives it through the `0xFF10` mailbox on `0x64`
      (write `{0x40, 0x00, 0xff, 0x10, 0xfd}`, read `0xfc`), with the hotkey.
      Our `0x62` command is a different mechanism and still unexplained, but
      there is nothing left to build. Take theirs.
      Old notes, if the `0x62` path is ever worth understanding: command known, driver blinks. Ideas in
      [keyboard-backlight.md](keyboard-backlight.md). **Lead:** ciscobugger's
      `EC2.sys` command descriptor table (payload lengths per command) may
      explain the blinking. Note their table covers only commands `>= 0x80`,
      while ours is `0x10` at address `0x62` — the dispatcher branches elsewhere
      below `0x80` and nobody has followed it. This is still the most clearly
      new thing we have.
- [x] **Touchscreen** works (found 1 Oct under KDE Plasma on the Anatase
      kernel): Goodix `27C6:0123` is a multitouch direct-touch device; the
      "mouse" and two "UNKNOWN" interfaces misled us. Still to check: GNOME,
      the Fedora kernel, and what the "UNKNOWN" interfaces are (pen? gestures?).
- [x] **Webcam** works with the experimental camera DTB (2 Oct): OV02C10 via
      CAMSS + libcamera software ISP; privacy LED on TLMM 110 lit while
      streaming. Open: libcamera tuning, browsers,
      power cost of the always-on GPIO hogs, upstreaming to Anatase.
- [ ] **Fingerprint reader**: not visible to Linux at all.
- [x] **EFI variables / NVRAM boot entries** work on the Anatase kernel (1 Oct); **RTC** set in UTC and verified across a reboot (1 Oct). Was: **EFI variables / NVRAM boot entries and the RTC** (clock resets each
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
- [ ] ~~**EC event queue** (0x62)~~ — Anatase now describes it in the device
      tree as `samsung,galaxybook4-edge-ec-events`, owned by the mailbox driver.
      Nothing for us to do; adopt their DTS.
- [ ] `deep` suspend never resumes (s2idle works; probably leave it).
- [ ] EC word at `0xb6` (37 on this unit): cycle-count candidate, watch whether
      it ever increments.

## To report upstream

Details in [upstream.md](upstream.md):

- [x] **Talk to ciscobugger**: issue opened 1 Oct, ciscobugger/book4-edge-linux#3 (15.6" NP750XQA) — highest value per minute of
      anything on this list; complementary gaps both ways. See
      [related-work.md](related-work.md) and the last section of
      [upstream.md](upstream.md).
- [x] Anatase: PD request retry after hot plug, and the cycle-count note:
      reported in https://github.com/anatase-org/kernel-anatase/issues/1
      (patch ready — note they are not
      the first to find it), cycle count register (`0xd0` is the state of charge
      here), and `CAPACITY` which could come from the gauge's own `0xa0`.
- [ ] Saddytech driver: design/last-full swapped, rate sign.
- [ ] ath12k / linux-firmware: WCN7850 firmware c7-00108 regression on this card.
- [ ] systemd/libinput: keyboard tagged as tablet pad.
- [ ] linux-arm-msm DTS thread: `pmic-glink` cannot work on this machine (and,
      if wanted, a tester's report on the v6 series).

## Carrying this elsewhere

- [ ] **Omarchy Dragon** — the clearest unoccupied space: nobody on that team
      owns a Samsung. Plan in [omarchy.md](omarchy.md). An issue on
      `omacom/omarchy` offering a working 14" and test cycles costs ten minutes
      and is the highest-leverage unspent thing here.
- [ ] Help get `samsung-galaxybook-ec` and `samsung-emuec` to mainline, even
      only as a tester. Until they land, every distribution needs a patched
      kernel for this laptop.

## Stale artefacts (30 September restructure)

- [ ] `dts/x1e80100-samsung-galaxy-book4-edge-14.anatase.dtb` predates the
      compatible change (`ene,kb9058-battery` -> `samsung,galaxybook4-edge-ec`).
      Rebuild from their current tree.
- [ ] `drivers/anatase/` carries `ene-kb9058-battery.c`, which no longer exists
      upstream. Replace with `samsung-galaxybook-ec.c` or drop it in favour of
      a local kernel build ([kernel.md](kernel.md)).
- [ ] `userspace/boot/99-book4-devicetree.install` takes the DTB from
      `/usr/lib/firmware/book4/`; with a locally built kernel it must take the
      one the build produced.

## Repository

- [x] Licence chosen 1 Oct: our code GPL-2.0-only, docs CC BY 4.0 (LICENSE, LICENSES/). Was: Choose a licence for our own files (drivers are GPL-2.0-only, the UCM
      profile BSD-3-Clause; scripts and docs have none yet).
- [x] Reviewed and published: the repository is public since 1 October 2026.
      Shared 1 Oct: zensanp/linux-book4-edge #3 (Wi-Fi), #4 (battery), #8
      (audio); ciscobugger/book4-edge-linux#3; a link on anatase-org/kernel-anatase#1.
      Fedora Discussion, 2 Oct:
      https://discussion.fedoraproject.org/t/fedora-45-on-the-samsung-galaxy-book4-edge-14-snapdragon-x-elite-what-works-and-how/203466
- [ ] Import the device tree **sources** (only compiled DTBs are here; the
      sources are on the workstation / in Anatase's tree).
- [ ] Try another distribution (the repo is Fedora-only so far). The hardware
      layer (`dts/`, `firmware/`, `userspace/audio`, `userspace/keyboard`,
      `userspace/modprobe`) is already distribution-neutral; only the glue
      (`userspace/dnf`, `userspace/dracut`, `userspace/boot`, `install/`) is
      Fedora. An `install/install-omarchy.sh` beside the Fedora one is the
      shape. Omarchy Dragon has nobody on a Samsung — see
      [related-work.md](related-work.md).
