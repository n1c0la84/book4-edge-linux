# Roadmap (17 November 2026)

The single list of what to do on this laptop, in order, and where it is
heading. It replaces `PLAN.md`. Evidence and history are in
[STATE.md](STATE.md), [TODO.md](TODO.md) and [power.md](power.md); the hard
rules in STATE.md apply to everything here (the assistant has no sudo, never
delete from the ESP, ask before posting anywhere).

## Where it is heading

**Stock Omarchy, plus a Book4 layer on top.** Stock means Omarchy's
repositories, Omarchy's kernel (`linux-omarchy`), Limine as boot loader,
Omarchy's updates and migrations. The layer is everything specific to this
laptop that stock does not have, packaged so it installs on a stock system
and survives its updates:

| Part of the layer | What | Lives today in |
|---|---|---|
| `book4-edge` package | UCM and PipeWire audio (speakers, mic noise suppression), udev rules (keyboard, fingerprint, battery boost), modprobe (`qcom_adsp_pwr_lmts` and battmgr blacklists), sleep log, battery warnings, crash log, Bluetooth address, fingerprint import, kbd backlight, the hooks we keep | `userspace/` |
| `book4-edge-firmware` (local only, never published) | ADSP/CDSP/GPU/Wi-Fi board/camera/sensor files from this laptop's own Windows partition | `install/arch/sync-*`, `firmware/` |
| `book4-edge-dkms` (shrinks to nothing) | drivers until they are in `linux-omarchy`: `samsung-galaxybook-ec`, `samsung-emuec`, `aoss_cxsd_only` (until `prevent_aoss_sleep` is set by default) | `drivers/anatase/`, `tools/power/sleep-modules/` |
| `book4-edge-el2` (optional) | the EL2 boot chain (UEFI Shell, qebspil, slbounce, `tcblaunch.exe` from Windows) as a Limine entry: KVM and the 0.70 W sleep | `install/el2/` |

A stock install on the 14" today: boots to the installer at EL1 and picks
our tree by itself (17 November), but has no Wi-Fi, GPU, sound or CDSP
firmware in the image, no Samsung EC drivers (no battery or charger
control), keeps AOSD on (which lost the disk in one deep suspend here) and
loads `qcom_adsp_pwr_lmts` (which crashes this ADSP). Each of those is a
line in "Kernel and upstream" below; the layer covers them until upstream
does.

## 1. Next, when you're back (owner, short)

1. **Fingerprint:** in Windows, Settings > Accounts > Sign-in options >
   Fingerprint, enroll. Back on Arch: `bash install/arch/fingerprint-import.sh`
   (installs the import, shows what the sensor holds), then try login,
   lock screen and sudo. Never enroll the same finger in Linux as well.
2. **Test antheas's reworked drivers** while he goes through our issues:
   the assistant builds his `samsung-emuec` and `samsung-galaxybook-ec` for
   our 7.2 kernel as modules (as `tools/kernel/update-sleep-emuec.sh` does).
   Then: plug/unplug the charger awake, charge from low, one sleep with an
   unplug during it (issue #3), and report on kernel-anatase.
3. **mako:** `sudo pacman -R mako` (it can grab the notifications at login).
4. **Clean up:** `bash tools/experiments/omarchy-kernel-test.sh undo`
   (the failed test entry); the Omarchy image can be deleted from
   `~/Downloads/omarchy-nightly/` once birkskyum has answered.

## 2. The ~0.6 W of board power in sleep (one night each, on battery)

Windows 0.11 W, Linux 0.70 W, SoC collapsed in both; a Zenbook A14 with the
same patches reaches 0.15 W, so it is this board's devices. The sleep log
tags each night.

1. GPIO 49 (`HPDC`): `bash tools/power/hpdc-test.sh`, a night, then `undo`.
   The one step of Windows' standby sequence never tried.
2. Airplane mode before closing the lid.
3. Touchscreen rail: boot `el2-nomisc`.
4. Then from the regulator tree (TODO.md, board power item): USB-C PHYs
   ("HS-PHY not in L2" at every suspend), the Wi-Fi port ("Timeout waiting
   for L2 entry"), the PTN3222 repeater, `VREG_WCN_3P3`, `vreg_l12b_1p2`,
   camera supplies, mic bias. linux-omarchy carries dwc3-qcom and qmp-combo
   suspend fixes (its 2350-2357, 2374-2376) worth comparing.

## 3. Omarchy 4.5 and Omarchy's repositories (step 1 towards stock)

Review: TODO.md, "Omarchy 4.5 and Omarchy's own repository". In a btrfs copy,
so the daily system is untouched:

1. `bash install/arch/omarchy45-copy.sh`, reboot, pick "... - test:
   omarchy45" (`findmnt -no FSROOT /` must print `/arch-45`).
2. In the copy: `bash install/arch/omarchy45-upgrade.sh` (pacman.conf:
   `[omarchy]` first, holds lifted, NoExtract extended; installs 4.5.0),
   log out and in, then `... migrate` (say no to anything about
   reinstalling configs or the boot loader), then `... check`.
3. Check: bar, menu, notifications, battery widget (our battery patch is not
   in the stock package: if it fails, send `userspace/omarchy/patches/0001`
   to omacom/omarchy), sleep and resume, Hyprland config errors.
4. Then `omarchy45-copy.sh adopt` (makes the copy the daily system) or
   `undo`. Afterwards a full `pacman -Syu` against Omarchy's repository
   (quickshell and yt-dlp move to Omarchy's builds; Hyprland: theirs is
   older, decide then), and folio/flea update through pacman.
5. Fix or drop the `iamcheyan.launcher` plugin (it shows every "pick one"
   menu as the apps grid; Super+K is worked around).

## 4. Kernel: from our 7.2 to Anatase's 7.3, then to linux-omarchy

**Port analysis, 17 November** (our 45 sleep-backport patches against
Anatase's `anatase` branch, 7.3.4, `00dbccf779`):

- **Already in 7.3 (15):** 0001-0009 (PDC series, domain_ss3), 0011-0014
  (LPASS tx/rx macros, geni force suspend), 0024-0025 (VA/WSA macros).
  Dropped on the move.
- **Apply as they are (22):** 0010 (PDC mode log), 0015-0016 (system-sleep-
  only genpd state, SS1), 0017 (syscon XO), 0018 (panel supplies), 0020,
  0026 (SoundWire irq sync), 0027-0028 (SHM bridge for EL2), 0029-0034,
  0036 (memlat), 0037-0039 (boost, capacity, 95 C), 0042 (speaker PA 23),
  0044 (KVM DC ZVA), 0045 (arch timer deadline, not built yet).
- **Need rework (8):** 0019, 0021-0023 (remoteproc attach for EL2: 7.3 has
  upstream `qcom_pas_attach`, so probably replaced by it plus the
  broken-reset bit), 0035 (memlat driver), 0040 (Iris without TZ PAS at
  EL2), 0041 (dspsignal), 0043 (DC ZVA erratum: 7.3 has only the Oryon
  CNTVOFF erratum, so a straight port into `cpu_errata.c`).
- **Plus our drivers/anatase patches:** antheas's rework covers most;
  orientation (#6), battery refresh on read and the 14" DT changes are
  with him (kernel-anatase#1).

**Port started 17 November.** Branch `book4/7.3` in our fork
(n1c0la84/linux-book4-edge), 32 commits on Anatase `00dbccf779`:
- the 22 clean sleep-backport patches;
- 0043 DC ZVA (only the cpucaps line needed placing by hand);
- 0019/0021-0023 replaced by one small patch on 7.3's own attach support
  (`qcom,broken-reset`: attach to the DSPs qebspil started, never restart);
- 0035 memlat (MAINTAINERS hunk dropped);
- our 14" DT: CCI0/CAMSS and the camera apply as they are; tweeters,
  fingerprint, woofer names and the absent repeater re-applied on the new
  layout (the 14" DTS now only overrides the shared x1e dtsi);
- samsung-emuec orientation (#6) on antheas's reworked driver.
Not ported yet: 0040 Iris at EL2 and 0041 dspsignal (7.3 moved Iris to the
generic PAS API; video decode and the NPU only), battery refresh on read
(his rework restructured the driver; wait for his answer). Not built yet:
no build has been run, so compile errors are still possible (the DT
overrides especially).

Steps:
1. Build and install next to the daily kernel:
   `bash tools/kernel/build-73-kernel.sh` (Fedora container, tree in
   Fedora's home `~/src/linux-73`, config from the 7.2 sleep kernel plus
   his SPSS TPM options; entry "... - test: el2-73"; `undo` removes it).
2. Test on it: `bash tools/kernel/check-73.sh` (DSPs, sound, battery and
   USB-C through his drivers, Wi-Fi, camera, fingerprint, KVM, TPM, EFI
   variables, sleep modules, errors), then a sleep on battery (0.70 W
   expected; whether his SPSS TPM driver changes the hourly visits).
3. Make it daily; the 7.2 kernel stays as fallback.
4. In parallel, upstream (each is a line on the way to stock):
   - linux-omarchy: `qcom_aoss.prevent_aoss_sleep` on by default for the 14"
     (omacom/omarchy#19044); Anatase's EC drivers and their DT nodes
     (asked 17 November); the ADSP power-limits message off for this model;
     the firmware gaps in the image; answer on battmgr.
   - Anatase: our open issues #2-#6 and the four in #1.
   - linux-arm-msm: birkskyum sends the `aoss_slp` format fix (credited);
     our CL5 / DRIPS / CNTV findings (draft in `docs/drafts/`, owner
     undecided).
5. When linux-omarchy carries the drivers and the sleep pieces: boot it
   with the layer (Limine entry), compare, and drop our kernel.

## 5. Boot: GRUB and Fedora out, Limine in

Today Fedora owns `/boot` (sda4) and GRUB, and is the kernel build
container; the EL2 chain chainloads Fedora's GRUB.

1. Kernel builds without Fedora: an Arch container or plain makepkg for the
   fork (a `linux-book4` PKGBUILD, long on the list); move
   `~/src/patchwork` out of Fedora's home first.
2. Limine on the ESP as Omarchy installs it (UKI per kernel, snapper
   entries), with our kernel(s) as entries; the EL2 chain's
   `startup-esp.nsh` then chainloads Limine instead of GRUB. Test from a
   second firmware boot entry before changing the default. Never delete
   from the ESP (hard rule): GRUB's files stay until everything is proven.
3. Retire Fedora: back up its home (22 GB, mostly the kernel tree), delete
   the `root` and `home` subvolumes, give sda4 to the ESP or Arch.
   Frees about 25 GB.
4. Disk space: shrink Windows from Windows (354 GB) and add the space to
   btrfs as a second device, or as a data partition. Back up home first.

## 6. Features still to do

- **Ambient light sensor** (VEML3328 behind the ADSP): Rafael's way
  (SB4-Edge-Linux `overlay/sensors`, `build-ssc.sh`): `adsprpcd sensorspd`
  with the sensor registry from the Windows driver files, libssc,
  iio-sensor-proxy 3.9; then a small service for screen and keyboard
  backlight (Omarchy has no automatic brightness). Try at EL1 first (his
  notes: the ADSP asserts if it can't write its registry; at EL2 a crashed
  DSP stays down until reboot).
- **External monitor over USB-C** (AUX timeouts; Rafael has the same
  failure on the 16"; linux-omarchy has many DP/PHY fixes).
- **Headset microphone** on the jack.
- **NPU** (dspqueue hang; dspsignal written, untested).
- **Speaker VI feedback** (right pair works on the test branch).
- **Hibernation** (resume resets; low priority).
- **USB-C controller failing after sleep** (TODO.md).

## 7. Waiting on others

- birkskyum (omarchy#15860): ADSP image source and battmgr; whether
  linux-omarchy takes Anatase's drivers; the AOSD default for the 14".
- antheas (kernel-anatase#1-#6): his answers this week.
- turbineBMW (omarchy-pkgs#1315): the EL of the SP11 result (no longer
  important).

## 7b. Found here, not told upstream yet (17 November)

| What | To whom | State |
|---|---|---|
| memlat on Hamoa (0036), 4 GHz boost (0037), CPU capacities (0038), 95 C passive trip (0039) | birkskyum, Anatase | posted to birkskyum 17 Nov (discussioncomment-19681553); Anatase not yet |
| Iris video decoding at EL2 without TZ (0040) | jglathe#102 / x1e-sleep (EL2 users only) | not drafted |
| SPSS hourly visits; AOSD failure modes; only the `val:` QMP form works | x1e-sleep, jglathe#102 | draft `docs/drafts/2026-11-16-jglathe-102-note.txt` |
| s2idle at EL1 needs CNTV armed unmasked | linux-arm-msm | draft `docs/drafts/2026-11-14-linux-arm-msm-el1-s2idle-cntv.txt` |
| keyboard tagged as tablet pad (`0CF2:9050`) | systemd hwdb | not drafted |
| WCN7850 firmware c7-00108 regression on this card | ath12k / linux-firmware | not drafted (docs/firmware.md) |
| EC battery reading collapsing from ~8 % to 0 under load | antheas | not drafted |
| primary USB-C controller failing after sleep | antheas / linux-arm-msm | needs investigation first |

## 8. Drafts not posted (owner's decision)

- `docs/drafts/2026-11-14-linux-arm-msm-el1-s2idle-cntv.txt` (kernel list).
- `docs/drafts/2026-11-16-launchpad-2084591-14inch.txt` (Rafael's bug).
- `docs/drafts/2026-11-16-jglathe-102-note.txt` (Jens Glathe's thread).

## Not worth doing

- AOSD: fails here in three different ways and saves nothing measurable
  elsewhere. Off everywhere.
- Starting the DSPs from Linux at EL2 (x1e-dsp): only useful for AOSD.
- The daily system at EL1: no KVM, nothing gained in sleep.
