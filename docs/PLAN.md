# Plan (written 16 November 2026)

What is prepared and what to do next, in order of value. Written so that any
session can pick it up: each item names the script, what to expect and where
the result goes. Background and evidence are in [STATE.md](STATE.md),
[TODO.md](TODO.md) and [power.md](power.md); the hard rules in STATE.md apply
to everything here (no sudo for the assistant, never delete from the ESP,
ask before posting anywhere).

Where things stand: the daily system is Arch + Omarchy 4.0.4 on our kernel
`7.2.7-book4s` at EL2, s2idle, AOSD off: 0.70 W asleep, deep sleep 100 %.
Windows on the same board sleeps at 0.11 W. Deep sleep also works at EL1
(0.77 W in s2idle with the CNTV arming, 0.84 W in deep), always with AOSD
off. Omarchy's edge kernel now has the AOSD switch we asked for.

## 1. Waiting on the owner (minutes each)

- **Answer birkskyum** in omarchy#15860 (his reply of 16 November 13:36): he
  asks which e-mail address to use for `Reported-by` / `Tested-by` on the
  linux-arm-msm patch. The assistant's session refuses to post an address,
  so the owner posts it.
- **Fingerprint**: the sensor holds no prints (16 November). Enroll the
  finger in Windows Hello, then on Linux run
  `bash install/arch/fingerprint-import.sh` once (installs the import and
  shows what the sensor holds). Never enroll the same finger in both
  systems. Background: TODO.md, fingerprint item; script from Rafael
  Meneses' SB4-Edge-Linux.
- **mako**: `sudo pacman -R mako` (it can grab the notifications at login
  before the Omarchy shell does; nothing depends on it).

## 2. Omarchy's own image on this laptop (the clean test; birkskyum is waiting)

First try, 17 November: linux-omarchy 7.3-70 with Omarchy's 14" DTB from our
GRUB with an initramfs we built (`tools/experiments/omarchy-kernel-test.sh`):
first boot lines, then black for 3 min, power held; nothing reached the
journal. Not a clean test (our initramfs and boot path). Remove that entry
with `bash tools/experiments/omarchy-kernel-test.sh undo`.

The clean test is Omarchy's nightly ARM installer image (one image for every
ARM machine, kernel 7.3.0-66+ with `qcom_aoss.prevent_aoss_sleep`):

1. `bash tools/experiments/omarchy-nightly-stick.sh fetch` (8.2 GB, resumable,
   checksum checked), then plug in a stick of 16 GB or more and
   `bash tools/experiments/omarchy-nightly-stick.sh write /dev/sdX`
   (refuses anything that is not a USB disk; asks you to type the device).
2. Power off, F10 at power-on, pick the stick. Do NOT install.
3. Note: how far it gets (boot menu, kernel, screen, installer), keyboard,
   touchpad, Wi-Fi. If it reaches the installer, switch to a console
   (Ctrl+Alt+F2, or the installer's shell) and save the log to a second USB
   drive: `mount /dev/sdb1 /mnt && journalctl -k -b > /mnt/omarchy-14.log &&
   cat /proc/cmdline >> /mnt/omarchy-14.log && umount /mnt`.
   `cat /sys/module/qcom_aoss/parameters/prevent_aoss_sleep` (Y or N).
4. Back on Arch: redact the log (MACs, IPs, SSIDs, serials; the `report`
   function in `omarchy-kernel-test.sh` has the sed lines), then post.
   Draft for birkskyum: `docs/drafts/2026-11-17-birkskyum-14inch.txt`
   (fill in the result first).

## 3. Omarchy 4.5 from Omarchy's own repository

Review: TODO.md, "Omarchy 4.5 and Omarchy's own repository". Two scripts:

1. `bash install/arch/omarchy45-copy.sh` makes a writable btrfs copy of the
   system (`arch-45`, home included) and the entry "... - test: omarchy45"
   (same kernel, EL2). Reboot normally and pick it;
   `findmnt -no FSROOT /` must print `/arch-45`.
2. In the copy: `bash install/arch/omarchy45-upgrade.sh` (pacman.conf:
   NoExtract extended, `[omarchy]` first, holds lifted; installs
   omarchy/omarchy-settings 4.5.0; checks). Log out and in, look around,
   then `bash install/arch/omarchy45-upgrade.sh migrate` (112 migrations;
   say no to anything about reinstalling configs or the boot loader).
3. To check in the copy: `omarchy45-upgrade.sh check`; Hyprland config
   errors; the bar, menu and notifications (our third-party plugins:
   `iamcheyan.launcher` replaces the menu and breaks pickers, see TODO);
   battery widget (our battery patch is not in the stock package: if the
   check says the battery is not found, send
   `userspace/omarchy/patches/0001` to omacom/omarchy); sleep and resume.
4. Then either `omarchy45-copy.sh adopt` (prints the steps to make the copy
   the daily system) or repeat the upgrade on the daily system, or
   `omarchy45-copy.sh undo`.
5. Open decisions: Omarchy's Hyprland is 0.56.2, ours 0.57.1 (kept);
   `quickshell` moves to Omarchy's patched build with a full update; folio
   and flea then update through pacman.

## 4. The ~0.6 W of board power in sleep

Windows 0.11 W, Linux 0.70 W, the SoC collapsed in both. A Zenbook A14 with
the same patches reaches 0.15 W, so it is this board's devices. One test per
night on battery (the gauge needs 6 h+ for ±0.1 W); the sleep log records
each night with its tag.

1. **GPIO 49 (HPDC)**: `bash tools/power/hpdc-test.sh`, sleep a night,
   compare with 0.70 W, `hpdc-test.sh undo`. It is the one step of Windows'
   standby sequence never tried (MODS/GPIO 44 alone made no difference).
2. **Airplane mode** before closing the lid (the log records the radios).
3. **Touchscreen rail**: boot `el2-nomisc`.
4. Then, from the regulator tree read on 16 November (TODO.md has it):
   - both USB-C controllers log "HS-PHY not in L2" at every suspend and the
     Wi-Fi port "Timeout waiting for L2 entry": PHYs or reference clocks
     may stay up. linux-omarchy carries dwc3-qcom and qmp-combo suspend
     fixes (its patches 2350-2357, 2374-2376): compare on its kernel
     (item 2), which also bears on the USB-C controller failing after sleep;
   - the eUSB2 repeater (PTN3222, `5-004f`, l4b + l13b) stays supplied;
   - always-on with no consumer: `VREG_WCN_3P3` (Wi-Fi/BT chip),
     `vreg_l12b_1p2`, l7b/l10b (camera), mic bias on `vreg_bob1`.
   UFS already sleeps at its deepest level (`spm_lvl` 5).

## 5. Smaller things, ready or nearly

- **Microphone noise suppression**: installed for the user on 16 November
  (`~/.config/pipewire/pipewire.conf.d/book4-mic-ns.conf`, default input
  "Microphone (noise suppression)"). To undo: delete the file,
  `systemctl --user restart pipewire pipewire-pulse wireplumber`.
- **Ambient light sensor**: not started. Rafael's way (SB4-Edge-Linux,
  `overlay/sensors`, `build-ssc.sh`): Qualcomm's `adsprpcd sensorspd` serving
  the sensor registry from the Windows driver files, libssc, iio-sensor-proxy
  3.9. Needs the 14"'s sensor files from our Windows partition, Arch builds
  of the three, and something in Omarchy to act on the readings. Try at EL1
  first: his notes say the ADSP asserts if it cannot write its registry, and
  at EL2 a crashed DSP stays down until reboot.
- **Super+K** is bound to a floating terminal list because
  `iamcheyan.launcher` shows every "pick one" menu as the apps grid
  (13 Omarchy commands use that menu). Fix the plugin or drop it.
- **Disk**: 73 % used after the cleanup. Windows has 354 GB. Plan: shrink
  Windows from Windows, then either add the freed space to the btrfs
  filesystem as a second device (no move; both initramfs must find it) or
  use it as a data partition. Back up the home folder first.
- **Kernel list**: `docs/drafts/2026-11-14-linux-arm-msm-el1-s2idle-cntv.txt`
  (s2idle under Gunyah needs CNTV armed, unmasked) is not sent; the owner
  is undecided. Patch 0045 does the same in the kernel, not built.
- **Mac mini M2** (omacom/linux-aurora#217, our HDMI report): on 16
  November jordglob confirmed it on an M2 Pro and posted a user service
  that disables and re-enables the HDMI output when the EDID is empty at
  login. Could be tried on the M2; no reply needed otherwise.
- **Launchpad bug 2084591**: Rafael Meneses announced a working Ubuntu for
  the 16" and asked for 14" testers; a short 14" status with a pointer to
  the sleep work would fit there (owner's OK first).

## 5b. Anatase's reworked Samsung drivers (17 November)

He reworked `samsung-emuec` and `samsung-galaxybook-ec` on his 7.3.4 tree
and will go through our open issues this week. What it covers and what not:
TODO.md, Upstream. Posted 17 November under issue #1
(https://github.com/anatase-org/kernel-anatase/issues/1#issuecomment-6943264160),
including four changes never sent before; watch for his answers this week. Testing his drivers means either backporting both files to our
7.2 kernel (module-only build, like `update-sleep-emuec.sh`) or moving to his
7.3.4 tree (the "Move off 7.2" item, which also brings his SPSS TPM driver).

## 6. Not worth doing now

- AOSD (the deepest state): fails in three different ways here and saves
  nothing measurable elsewhere. It stays off.
- Starting the DSPs from Linux at EL2 (x1e-dsp): only useful for AOSD.
- Moving the daily system to EL1: no KVM, and nothing gained in sleep.
