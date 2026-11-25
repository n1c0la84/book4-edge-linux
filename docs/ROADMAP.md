# Roadmap (updated 19 November 2026)

The single list of what to do on this laptop, in order, and where it is
heading. It replaces `PLAN.md`. Evidence and history are in
[STATE.md](STATE.md), [TODO.md](TODO.md) and [power.md](power.md); the hard
rules in STATE.md apply to everything here (the assistant has no sudo, never
delete from the ESP, ask before posting anywhere).

## Where it is heading

**Stock Omarchy, plus a Book4 layer on top.** Stock means Omarchy's
repositories, Omarchy's kernel (`linux-omarchy`), Arch's own GRUB (Limine optional, later),
Omarchy's updates and migrations. The layer is everything specific to this
laptop that stock does not have, packaged so it installs on a stock system
and survives its updates:

| Part of the layer | What | Lives today in |
|---|---|---|
| `book4-edge` package | UCM and PipeWire audio (speakers, mic noise suppression), udev rules (keyboard, fingerprint, battery boost), modprobe (`qcom_adsp_pwr_lmts` and battmgr blacklists), sleep log, battery warnings, crash log, Bluetooth address, fingerprint import, kbd backlight, the hooks we keep | `userspace/` |
| `book4-edge-firmware` (local only, never published) | ADSP/CDSP/GPU/Wi-Fi board/camera/sensor files from this laptop's own Windows partition | `install/arch/sync-*`, `firmware/` |
| `book4-edge-dkms` (shrinks to nothing) | drivers until they are in `linux-omarchy`: `samsung-galaxybook-ec`, `samsung-emuec`, `aoss_cxsd_only` (until `prevent_aoss_sleep` is set by default) | `drivers/anatase/`, `tools/power/sleep-modules/` |
| `book4-edge-el2` (optional) | the EL2 boot chain (UEFI Shell, qebspil, slbounce, `tcblaunch.exe` from Windows) as a boot entry: KVM and the 0.70 W sleep | `install/el2/` |

A stock install on the 14" today: boots to the installer at EL1 and picks
our tree by itself (17 November), but has no Wi-Fi, GPU, sound or CDSP
firmware in the image, no Samsung EC drivers (no battery or charger
control), keeps AOSD on (which lost the disk in one deep suspend here) and
loads `qcom_adsp_pwr_lmts` (which crashes this ADSP). Each of those is a
line in "Kernel and upstream" below; the layer covers them until upstream
does.

## Status (19 November 2026)

| Step | State |
|---|---|
| 1. Kernel 7.3 daily, 7.2 in GRUB as the fallback | **done**. Release name fixed; deep sleep (CTCU off) and audio (c663014e45 reverted) fixed; Iris patch ported and working; battery refresh tested; DSP signalling (dspsignal) ported, not yet exercised (only the NPU uses it). Package linux-book4 7.3.4-3 |
| 2. Omarchy 4.5, its repositories, `omarchy-update` | **done** (btrfs copy `arch-45`, the default boot) |
| 3. Kernel packaged on Arch, Arch's own GRUB | **done**: `packages/linux-book4`, `book4-boot` and its pacman hooks write `/boot` and the menu; firmware entry "Omarchy (EL2, Arch GRUB)" first, Fedora's GRUB as fallback. Limine postponed (see "Fresh install" below) |
| 4. Retire Fedora | **done except the deletion** (archive in `~/fedora-archive`, [fedora-retired.md](fedora-retired.md)); Windows shrunk to 300 GB, root btrfs now sda5 + sda6, 196 GB |
| 5. Omarchy's own kernel with our patches as the Book4 layer | later, once linux-omarchy covers enough (section 4) |

Problems from these steps:

- **Iris**: works after a fresh boot (1080p H.264/HEVC clean); one odd-size
  stream (2832x1700) faults it until reboot. mpv decodes in software
  (`hwdec=auto-safe`), which loses nothing for H.264 and little for HEVC.
  Left like that.
- **Charger during sleep**: the unplug reset is fixed again on 7.3 and
  verified; waking for a charger plugged in during sleep is built, not tested.

## 1. Next (owner, short)

1. **Windows** (19 Nov: chkdsk done, fingerprints enrolled and imported).
   Still: start Windows from the firmware menu (F10), not from Arch GRUB
   (2.16's chainload fails: BCD 0xc00000bb), until the GRUB entry is fixed;
   next time in Windows, `bcdedit /enum firmware` and `bcdedit /delete` the
   "Fedora" object, or Windows puts that (hanging) entry first again.
   Done steps: boot it once (it runs chkdsk after the resize), then enroll
   fingers in Settings > Accounts > Sign-in options > Fingerprint (needs a
   PIN). Beforehand on Arch: `bash install/arch/fingerprint-import.sh`
   (the import service; not yet on the arch-45 copy). Back on Arch it imports
   at boot; check with `fprintd-list $USER`, then try login, lock screen and
   sudo. Enroll fingers only in Windows from now on.
2. **First Linux boot with root on two partitions** (sda5 + sda6): comes
   with the Windows round trip.
3. **7.3 at EL1**: done 23 November through Limine's EL1 entry (boots, DSPs, sound, GPU, charging; sleep at EL1 still to try).
4. **Wake on plug-in**: lid closed on battery, plug the charger in; it should
   wake briefly to negotiate, then sleep again (`samsung-emuec ... wake=1`).
5. **Fedora deletion**, when the new boot has run a few days: the `root`
   and `home` subvolumes (~23 GB back after the archive's share), its files
   on sda4. `\EFI\fedora\` stays on the ESP.

Done or obsolete since 17 November: antheas's reworked drivers are in our
7.3 kernel (the unplug fix ported back onto them); mako is gone; the
`omarchy-kernel-test.sh` entry and its modules are gone.

## Fresh install from the official Omarchy ISO (owner's plan, later)

Why Limine is postponed: when the official ISO lands, a fresh install in
its own space, rather than converting this system. It makes sense; plan for:

1. **Space**: no free partition now. Options: take sda6 back (`btrfs device
   remove /dev/sda6 /` moves its data to sda5; needs the data to fit, easier
   after the Fedora deletion), shrink Windows further, or a subvolume of the
   existing btrfs if the installer allows it.
2. **ESP of 260 MB** (checked 19 Nov: 116 MB free; Microsoft 28 MB, Fedora
   GRUB 10 MB, the rest small). Omarchy on Qualcomm builds one UKI per
   kernel with systemd-ukify, every x1/hamoa DTB embedded for
   `DeviceTreeAuto` (`install/hardware/qualcomm/dtb-uki.sh`), on the ESP via
   limine-mkinitcpio. Ours as a UKI would be about 100 MB (Image 61 MB,
   initramfs 39 MB): one fits, a second kernel or snapper's boot entries do
   not. Way out: a second, larger ESP for the new install (the firmware
   takes several; e.g. sda4, 2 GB, reformatted FAT32 once this system no
   longer boots from it, or part of the space the new install gets).
   Also open: the nightly ISO booted the 14" without our `cutmem`
   (17 Nov, EL1); whether an installed Limine/UKI boot needs it is unknown.
3. **What this machine needs to boot**: `cutmem 0x8800000000 0x8fffffffff`,
   a device tree per kernel, the EL2 chain through the UEFI Shell. Limine
   must provide all three; until it does, the new install can boot from our
   Arch GRUB with one more menu entry.
4. **The Book4 layer as packages first** (the table above). **Started 19
   Nov:** `packages/book4-edge` (userspace/: audio UCM and PipeWire/
   WirePlumber drop-ins, udev, modprobe, sleep log and EL2 sleep helper,
   battery warnings, Bluetooth address, crash log, GPU busy, fingerprint
   import, keyboard; helpers in /usr/lib/book4, units in /usr/lib/systemd)
   and `packages/book4-edge-boot` (book4-boot, its hooks, the EL2 overlay,
   windows.nsh); `install/arch/book4-edge-migrate.sh` moves this machine
   from the script-installed copies. Firmware packaged the same day
   (`book4-edge-firmware`, local only, staged from Windows by checksum), and
   all four go into a local pacman repository `[book4]`
   (`install/arch/book4-repo.sh`): a fresh install needs that directory,
   one Include line, `pacman -S linux-book4 book4-edge book4-edge-boot
   book4-edge-firmware`, `/etc/book4/boot.conf` and the EL2 chain. **Online
   since 20 Nov** ([packages-online.md](packages-online.md)): GitHub Actions
   builds the four public packages in an Arch Linux ARM container, signs them
   (key only in the repository secrets) and publishes `[book4]` in the release
   `repo`; the firmware stays a local build from Windows. Before: only the kernel was a package (`packages/linux-book4`, with the sleep
   modules and Samsung drivers inside, so `book4-edge-dkms` is not needed
   while we ship our kernel). Everything else installs by script from
   `userspace/` (audio UCM/PipeWire, battery, Bluetooth address, crash
   log, GPU busy, fingerprint import, keyboard and its backlight,
   modprobe, sleep hooks) and `install/` (firmware sync, EL2 chain,
   book4-boot). Next: `book4-edge` (userspace/, one PKGBUILD, files under
   /usr, services enabled by a post-install note), `book4-edge-boot`
   (book4-boot, its hooks, the overlay; the EL2 chain files stay a script:
   tcblaunch.exe comes from Windows), `book4-edge-firmware` built locally
   from this laptop's Windows partition, never published. The more is
   packaged, the easier the move; it is also step 5.

## Pending features

Section 6 below: ambient light sensor, external monitor over USB-C, headset
microphone, NPU, speaker VI feedback, hibernation, USB-C controller after
sleep.

## 2. The ~0.6 W of board power in sleep (one night each, on battery)

Windows 0.11 W, Linux 0.70 W, SoC collapsed in both; a Zenbook A14 with the
same patches reaches 0.15 W, so it is this board's devices. The sleep log
tags each night.

1. GPIO 49 (`HPDC`): `bash tools/power/hpdc-test.sh`, a night, then `undo`.
   Superseded (25 Nov) by `tools/power/ec-standby-test.sh`: MODS + HPDC
   together, as Windows does (RESP never reaches the EC). HPDC alone only
   if the combined night saves something.
   The one step of Windows' standby sequence never tried.
2. Airplane mode before closing the lid.
3. Touchscreen rail: boot `el2-nomisc`.
4. Then from the regulator tree (TODO.md, board power item): USB-C PHYs
   ("HS-PHY not in L2" at every suspend), the Wi-Fi port ("Timeout waiting
   for L2 entry"), the PTN3222 repeater, `VREG_WCN_3P3`, `vreg_l12b_1p2`,
   camera supplies (checked 19 Nov: the OV02C10 sits runtime-suspended
   with CCI, so the sensor is in reset; but its 2.8 V rail `vreg_l7b_2p8`,
   used by the camera alone for avdd and dvdd, is `regulator-always-on`
   with `regulator-initial-mode = <3>` (HPM), so it stays on in high-power
   mode through sleep; its 1.8 V `vreg_l10b_1p8` is shared IO. Expected
   milliwatts, not the 0.5 W; test: an overlay without always-on / in LPM,
   camera checked, one night), mic bias. linux-omarchy carries dwc3-qcom and qmp-combo
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
   `undo`. Afterwards a full update against Omarchy's repository with
   `omarchy-update`, not a bare `pacman -Syu` (4.5's
   `00-omarchy-update-guard.hook` blocks that unless
   `OMARCHY_ALLOW_DIRECT_PACMAN=1`). It prunes the cache to 2 versions,
   snapshots (no snapper here: continues without; the btrfs copy is the
   safety net), updates keyring and packages, runs `omarchy-migrate`, AUR,
   mise, and asks (default no) before removing orphans: answer no until the
   list is checked
   (quickshell and yt-dlp move to Omarchy's builds; Hyprland: theirs is
   older, decide then), and folio/flea update through pacman.
   **Done in the copy, 18 November:** Omarchy 4.5.0-3 from pkgs.omarchy.org
   (22 packages from [omarchy]); NoExtract held (no Limine/mkinitcpio files),
   battery found. Migrations: 1791403310 (titlebars) marked done by hand:
   `omarchy-hyprland-titlebars` pins Omarchy's hyprland 0.56.2, ours is Arch's
   0.57.1 (aquamarine 0.16.0 likewise newer than Omarchy's 0.15.1); the other
   47 ran (all Limine/N1x/ASUS ones skip themselves; power-profiles-daemon
   swapped for Omarchy's build). `ttfx` installed by hand (screensaver; its
   migration ran before our repo switch), `mise install` (node 26).
   **Name clash:** our locally built `folio` (omacom/folio file manager)
   vs the unrelated AUR `folio` 25.02: `omarchy-update` runs
   `yay -Sua --noconfirm` and would replace it, so `folio` is in IgnorePkg
   in the copy. checkupdates: nothing pending; AUR: artcraft-launcher
   0.14 -> 0.19.2. Orphans offered: build tools (meson, sassc, ...).
   `omarchy-update` ran (11:27): its 10 GiB free check fails (8.5 GiB, the
   copy diverged by ~7 GB), passed with `OMARCHY_UPDATE_FORCE=1`; orphans
   removed, artcraft updated. Folio: only in Omarchy's **edge** channel
   (0.6.1; stable has Flea; Nautilus stays the 4.5 default), installed with
   `pacman -U https://pkgs.omarchy.org/edge/aarch64/folio-0.6.1-1-aarch64.pkg.tar.zst`;
   keep `folio` in IgnorePkg until it reaches stable, then drop the hold.
   `omarchy-update-restart` always asks to reboot here: it looks for a
   pacman-owned modules.builtin and ours are not packaged; a false alarm.
   **Invisible pointer in X11 apps** (RealVNC Viewer's window): 4.5's startup
   cursor (`default/hypr/startup-cursor.lua`) starts blank and runs
   `xsetroot -cursor_name left_ptr` when it restores the real cursor; XWayland
   came up later (it still carried OMARCHY_STARTUP_CURSOR_SESSION), so the X
   root cursor stayed blank. `DISPLAY=:0 xsetroot -cursor_name left_ptr`
   fixes it live; made permanent with a delayed `o.exec_on_start` in
   `~/.config/hypr/autostart.lua`. Worth reporting to Omarchy.
   Next: a day or two in the copy, then `omarchy45-copy.sh adopt` or `undo`.
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
Ported 17 November (42dfc63, not built yet): 0040 Iris at EL2 (on 7.3's
qcom_pas API, fw init before the IOVA reservation), 0041 dspsignal (offsets;
callback hunk before 7.3's PD-exit check), battery refresh on read (redone
on antheas's reworked driver). Release name fixed in build-73-kernel.sh:
`7.3.4-book4` (CONFIG_LOCALVERSION only); a rebuild removes the old
`7.3.4-book4-book4` install. Not built yet:
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
   with the layer (its own boot entry), compare, and drop our kernel.

## 5. Boot: Fedora out, Arch's own GRUB in (Limine later, optional)

Detailed plan: [plan-arch-boot.md](plan-arch-boot.md) (18 November).

**Done 19 November** (parts A, B and C of the plan, Fedora's deletion still
pending; see Status above). Kept for the record:

Decided 18 November: two moves instead of one. Limine is not required by
Omarchy (only in the installer's `omarchy-other.packages`; every Limine
migration skips itself without it, 4.5 runs here on GRUB). Its benefit is
bootable snapper snapshots (`limine-snapper-sync`); the btrfs-copy method
used for the 4.5 upgrade covers that need for now.

1. Kernel builds without Fedora: a `linux-book4` PKGBUILD (makepkg on Arch,
   native aarch64), installable and removable with pacman; move
   `~/src/linux-73` and `~/src/patchwork-sleep` (7.2 fallback config) out
   of Fedora's home first.
2. **Arch's GRUB** (the `grub` package) on the ESP, as its own directory
   next to Fedora's, with a grub.cfg generated on Arch: the daily 7.3 entry,
   the 7.2 fallback, and `test-entry.sh` adapted to it. The EL2 chain's
   `startup-esp.nsh` chainloads it instead of Fedora's GRUB. Test from a
   second firmware boot entry before changing the default. Never delete
   from the ESP (hard rule): Fedora's GRUB files stay until everything is
   proven.
3. Retire Fedora: back up its home, delete the `root` and `home`
   subvolumes, give sda4 to the ESP or Arch. Frees about 25 GB.
4. Disk space: shrink Windows from Windows (354 GB) and add the space to
   btrfs as a second device, or as a data partition. Back up home first.
5. **Optional, later: Limine** (plan: [plan-limine.md](plan-limine.md), 22 Nov:
   split sda4 into ext4 + FAT32, Limine after the EL2 chain, GRUB kept) as Omarchy installs it (UKI per kernel,
   snapper entries), if boot-menu snapshots become worth the change; same
   rules (second firmware entry first, GRUB kept as fallback).

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

## 7a. First boot of el2-73 (17 November)

7.3.4 (Anatase + book4/7.3) boots at EL2: ADSP/CDSP attached, sound card,
Wi-Fi, Bluetooth, camera nodes, KVM, EFI vars, fingerprint reader (1c7a:05a1),
the Samsung EC battery/AC supplies and both Type-C ports, sleep modules and
book4-el2-sleep.service active, no failed units. Problems:

- **`qcom_spss_nvm` probe loop**: "cannot locate secure NVM partition"
  (-EINVAL) for `sec_nvm_sp_nvm` and `sec_nvm_stpm_lite_msft`, ~700 lines/s,
  journald and udev at 100 % CPU. Blacklisted in
  `/etc/modprobe.d/book4-spss-nvm.conf` (no effect on 7.2, which has no such
  module); so no SPSS TPM. To understand, then report to antheas.
- **Iris**: "firmware download failed -22": 0040 (non-TZ Iris start) not yet
  ported to 7.3; expected.
- Release name `7.3.4-book4-book4` (the double suffix, known).
- **No CX collapse in s2idle** (5 naps, 17 November: cxsd/ddr 0.0 %, against
  96-100 % on every 7.2 nap). APSS enters (1 entry per nap), ADSP/CDSP sleep,
  the system genpd requests DRIPS (S1, s2idle count 5; SS1 at runtime, as
  designed by 0015/0016), so a vote holds CX. Ruled out, one at a time:
  qcom_spss_nvm + qcom_glink_spss unloaded, qcom_iris unloaded, coresight
  unloaded, charger (a nap on battery). `tools/power/vote-dump.sh` on both
  kernels (awake): 7.3 has interconnect votes on the primary USB-C
  controller `a600000.usb` (1.0/2.5 GB/s on DDR/LLCC, 40 MB/s cfg) that 7.2
  lacks (on 7.2 that controller dies after sleep), an enabled `a80000.i2c`
  SE clock (touchpad bus, likely busy during the dump), small qup1 votes.
  18 November, rebuilt 7.3.4-book4 (Iris works, sound card on): naps still
  0 % with `a600000.usb` unbound, and with the Bluetooth UART (`a98000`,
  qup1 vote 25000 vs 2) unbound as well; awake votes then match 7.2. Not
  it either: the boot log's PDC/PSCI/timer lines and the command line are
  identical; the 12 reserved-memory regions 7.3's hamoa.dtsi dropped
  (7d240c5dd3, "covered by EFI") are still reserved or outside RAM in
  /proc/iomem; `arm,prefer-cpu-suspend` (cb723904b8/c2eb81d74b) only sets
  the default we already pass; rpmh-rsc is the same. Next, split the
  problem: the 7.3 kernel with 7.2's EL2 DTB (`test-entry.sh add 73-dt72
  kernel=/vmlinuz-7.3.4-book4 initrd=/initramfs-7.3.4-book4-arch.img
  dtb=/dtb-test/book4-sleep-el2.dtb -clk_ignore_unused -pd_ignore_unused`):
  collapse = the cause is in the DT (also covers the SPSS GLINK node, new on
  7.3), none = in the kernel code. **Result: 97.1 % (18 Nov 10:03)**, so the
  blocker is in 7.3's DTB. Bisecting by node group with
  `tools/power/dt73-variant.sh nocs|noadc|nospss` (7.3 EL2 DTB with that
  group disabled, own test entry). First: coresight (7.3 adds ETR/CTCU,
  8017f8fa34; unloading the modules threw clk disable warnings).
  **`73-nocs`: 98.4 % (18 Nov 10:11): coresight is the blocker.** 7.2 has
  coresight too (TPDM/funnels) and collapses, so the suspects are 7.3's new
  CTCU, ETRs and replicators (8017f8fa34), all clocked by `aoss_qmp`
  (the QDSS clock, voted through AOSS QMP). The CTCU driver enables its
  clock with devm_clk_get_optional_enabled() and also toggles it from
  runtime PM (unbalanced on remove: the warnings).
  **`73-noctcu`: 97.0 % (18 Nov 10:18). The CTCU alone is the blocker**
  (with it off, `qdss` shows enable count 0 awake, the other coresight
  drivers loaded). Fixed on book4/7.3 (f79c9d4, the 14" DTS disables
  `ctcu@10001000`); until the next build, boot "test: 73-noctcu" for 7.3.
  Not yet known: which reference keeps the QDSS clock voted with the CTCU
  probed (read `qdss` in clk_summary on a plain 7.3 boot to confirm).
- **Microphone broken on 7.3** (both DTBs): `Failed to start APM port 110`
  (VA_CODEC_DMA_TX_0, APM error on 0x01001002), retried hundreds of times;
  the speaker PCM then stays PREPARED in PipeWire (echo-cancel ties them).
  Speakers play with PipeWire paused (speaker-test, heard). 7.2 fine.
  Checked, the same on both: UCM mixer path (VA DEC0/1 MUX, DMIC MUX, AIF1
  CAP mixer all set), macro/dcodec/fsgen votes, lpass-va-macro and
  pinctrl-lpass-lpi (trivial diff), the topology/card boot messages, the
  codec-DMA channel mask (c663014e45 gives the same 0x3 for the default
  map, yet it is the cause, see below).
  **Found 18 November:** `audio-bisect-73.sh all` (12 7.3-only qdsp6 commits
  reverted, module build in updates/): mic records, music plays. Then only
  c663014e45 ("audioreach: compute active channel maps from channel_map")
  reverted: mic records (RMS 1236, no APM errors), music fine. Reverted on
  book4/7.3 (767f896). The updates/ modules match that until the next full
  build, which replaces the whole modules dir. Why it breaks VA capture is
  not understood yet (worth a report to linux-sound once understood).
- **Audio**: PipeWire had the card on profile "off" after boot (only the
  book4_speakers filter sink); `pactl set-card-profile alsa_card.platform-sound
  "HiFi (Headphones, Mic, Speaker)"` brought it back. Boot log: `qcom-apm CMD
  timeout`, "Parent card not yet available". Watch on the next boot.
- Still to do on it: speakers by ear, the USB-C ports after sleep.

**Rebuilt 18 November (book4/7.3 767f896, "el2-73"):** CTCU off from the
kernel's own DTB, audio revert in the build, no updates/ modules. Check
clean (DSPs, Iris decoder/encoder, sound card on, mic RMS 2864, music by
ear, errors as on 7.2); 2-minute nap on the charger **cxsd/ddr 96.6 %**.
Next: one long sleep on battery (target ~0.70 W like 7.2), then 2-3 days of
use (charger unplugged during sleep, USB-C hub/monitor, camera, a VM), then
`test-entry.sh default el2-73` with 7.2 kept as the fallback entry.

## 7b. Found here, not told upstream yet (17 November)

| What | To whom | State |
|---|---|---|
| memlat on Hamoa (0036), 4 GHz boost (0037), CPU capacities (0038), 95 C passive trip (0039) | birkskyum, Anatase | posted 17 Nov: birkskyum (discussioncomment-19681553), Anatase (kernel-anatase#1) |
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
