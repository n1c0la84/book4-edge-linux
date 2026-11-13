# State

**Updated 13 November 2026**: CL5/DRIPS comparison measured (EL2, book4s
kernel, battery, radios on; details in [TODO.md](TODO.md)): A (Omarchy
shape, no CL5, no system state) 6.18 W awake, 1.46 W asleep, cxsd 0 %;
B (daily: CL5 + SS1/DRIPS) 5.97 W, 0.70 W, cxsd 100 %; C (no CL5,
SS1/DRIPS kept) 6.05 W, 2.27 W, cxsd 0 %. Posted 13 November
(omarchy#15860 discussioncomment-19584893, edited the same day: the
result holds at EL2 only, with the rejection counts; mainline v7.3
`system_pd` has DRIPS only, so linux-omarchy is about C). **Re-read of the whole sleep
work, 13 November (TODO.md, CL5/DRIPS item):** C spins: TrustZone refused
DRIPS 1.63 billion times that night (system states need the clusters in
CL5 at EL2); that says nothing about EL1, where linux-omarchy reports
full collapse with the CL5 drop on a Surface Pro 11 and a Slim 7x; our
"EL1 never collapses" rests on one test made before the last blocker was
fixed; two B sleeps without collapse were probably a KVM guest left
running. **EL1 deep sleep reached the same day** (entry `el1-sleep`,
`tools/experiments/el1-sleep-prep.sh`): first no collapse (1.42 W,
`apss` 0), then, with `cntv_arm` arming CNTV unmasked (Gunyah ignores a
masked vCPU timer), `apss`/`cxsd`/`ddr` 97.9 % of a 141 s sleep, and
**0.77 W with `cxsd` 100 % over 127 min on battery** (EL2: 0.70 W),
reported in omarchy#15860 (discussioncomment-19594936). birkskyum: the
other machines' EL1 collapse was `deep` (SYSTEM_SUSPEND); their s2idle
fails like ours did. **Late 13 November, EL1:** x1e-crash ran 10 min
with CL5 in use, no reset; a `deep` suspend resumed cleanly with `cxsd`
97.4 % and no timer module. Next (plan in TODO.md): report both, the
`masked=1` control; then CL5 dropped at EL1, the CNTV arming as a kernel patch, the blog post's EL1
claim, the VM check, a Windows
battery-standby figure for the ~0.7 W, the Omarchy edge image with one
suspend, then `el2-dt-test.sh omshape|nocl5 undo` and
`test-entry.sh remove el1-sleep`. Still pending: the Omarchy edge image boot test (live only) when
birkskyum links it. The one page to read at the start of every
working session on this machine, and to update (with the commit) at the end.
Details live in the linked docs; open work in [TODO.md](TODO.md); history in
`git log`.

## How the machine runs today

- **Hardware:** Galaxy Book4 Edge 14" NP940XMA (X1E80100), 476.7 GB UFS:
  `sda1` ESP (260 MB, shared with Windows), `sda2` MSR, `sda3` Windows,
  `sda4` ext4 `/boot` (Fedora's; holds the kernels and DTBs of both Linuxes),
  `sda5` btrfs with subvolumes `root` (Fedora 45) and `arch` (daily).
- **Daily system:** Arch Linux ARM + Omarchy 4.0.4 (local build,
  [omarchy.md](omarchy.md)), sleep kernel `7.2.7-book4s` (branch
  `book4/7.2-sleep` of n1c0la84/linux-book4-edge,
  `tools/kernel/sleep-backport/`), **at EL2**: firmware entry "Book4 EL2
  (slbounce)" -> UEFI Shell in `\EFI\book4-el2\` (qebspil + slbounce) ->
  Fedora's GRUB -> entry `el2-sleep` ([el2.md](el2.md)).
- **Kernel base:** on end-of-life 7.2 by choice (5 November); revisit if 7.4
  becomes long-term, findings in [TODO.md](TODO.md).
- **Primary USB-C controller can fail after sleep** (7 November): see TODO.md.
  Workaround: use the other USB-C port, or reboot.
- **Android development:** Google Android CLI `1.1.16717390` for Linux ARM64
  is installed at `~/.local/bin/android`; its SDK root is `~/Android/Sdk`
  (31 October 2026).
- **Flea file manager** 0.4.0, built locally (4 November): upstream ships it
  only in the x86_64-only Omarchy Package Repository, so `omarchy pkg add
  flea` fails here and `omarchy update` never updates it. Rebuild each
  release with `install/arch/flea.sh <version>`.
- **Updates:** `book4-update` (`userspace/update/`, installed by
  `install/arch/update.sh`) instead of `omarchy update`: cache prune,
  read-only snapshot via `tools/backup/snapshot-arch.sh` (`arch-pre-update-*`, 2 kept;
  rollback steps in `book4-update --help`), `pacman -Syu`, `yay -Sua`,
  `mise up`, then Hyprland config check, .pacnew, orphans, pending Omarchy
  migrations and a newer flea release. `--check` lists what is pending.
  Snapshots now (4 November): `arch-pre-omarchy-20261003-1109` (0.7 GB of
  its own) and `arch-pre-update-20261104-0934`; Fedora's `root` + `home`
  hold ~22 GB (the kernel tree `~/src/patchwork` is in Fedora's home).
- **Pacman:** full `-Syu` on 4 November (113 packages, clean; mkinitcpio
  stays IgnorePkg). Checked first as boot-safe: Arch has no kernel package,
  no mkinitcpio preset and no `pkgbase`, so pacman hooks write nothing to
  Fedora's `/boot` or the ESP; Book4 firmware is in
  `/usr/lib/firmware/updates/` (no package owns it), and the one packaged
  file the GPU loads, `qcom/gen70500_gmu.bin`, was byte-identical. Hyprland
  0.57.1 passed `--verify-config` on our Lua config; upgrade its stack as a
  whole. The cache keeps one version per package, plus the previous
  Hyprland stack and mesa for a `pacman -U` rollback (drop them with
  `paccache -rk1` once 0.57 has run a few days).
- **Fedora:** owns `/boot` and GRUB, and is the kernel build environment
  (Arch builds in a Fedora container, `install/arch/fedora-shell.sh`). The EL1
  kernel `7.2.7-book4` stays: Fedora's default and the kernel to build
  `book4s` from (`build-sleep-kernel.sh` refuses to run on `book4s`).

## What works (EL2, book4s)

Deep sleep in s2idle with both DSPs (board ~0.9 W, [power.md](power.md));
four speakers at PA 23 (+12 dB, about Windows' level) with crossover, woofer
high-pass and silent pilots ([audio.md](audio.md)); camera; fingerprint;
Iris hardware video decode; EFI variables and RTC; KVM; battery and charging
through the Samsung EC, awake charging included since 29 October (PD contract
passed to the EC, [ec-protocol.md](ec-protocol.md)); Wi-Fi (firmware c5-00302,
[firmware.md](firmware.md)).

Low battery: Omarchy warns at 10 %, `book4-battery-warn` at 8 % and 5 %,
UPower powers off at 3 %. Under heavy load the EC's reading drops from ~8 %
to 0 in seconds (30 October, all cores busy: dead at "8 %"), so plug in at
the 8 % warning.

Charging through a powered USB-C hub does not work (4 November): the
laptop is the power source on that port, the partner shows no USB PD and
no `PD contract` is logged, so the input-limit fix never runs. Replugged
with its charger already in (14:21): the same. The hub is a VIA VL817
(2109:2817). Next: does it charge a phone, or the laptop under Windows?

Not working: external monitor over USB-C (AUX timeouts); NPU inference
(dspqueue hang; dspsignal port 0041 written, untested).

## In progress

- **Live ISO and reset installer** (29-30 October,
  [install.md](install.md#undo-and-recovery)): `install/arch/live-iso.sh`
  builds `~/book4-live.iso` (private: tcblaunch.exe and Windows firmware
  inside; rebuilt 4 November with the DC ZVA kernel). First boot of the
  stick (4 November): EL1 works (long black screen first); EL2 loops
  GRUB -> slbounce -> GRUB without a reset (the second GRUB showed the
  first menu; it now loads its own `grub-el2.cfg`, EL2 entries only); `book4-install` refused, which
  exposed a keep-list bug that put the MSR (sda2) on the wipe list (fixed,
  plus a refusal for unknown partitions without a filesystem); checked against this disk's real table afterwards: keeps sda1-3, wipes only sda4-5. With the
  stick plugged in, the internal "Book4 EL2" Shell picked the stick's
  `\EFI\book4-el2\` and stopped at `FS3:\>` (startup-esp.nsh now also
  requires `\EFI\fedora\grubaa64.efi`; the ESP copy is updated by
  `~/book4-boot-check.sh`). Arch EL1 ("Arch Linux (7.2.7-book4)") hung
  after GRUB without reaching the root filesystem (no log). That entry is
  stale: old EL1 kernel, Arch initramfs of 10 October, unused since EL2
  became daily (every logged Arch boot since 21 October is book4s at EL2).
  Arch EL1 fallback since 4 November: GRUB entry "Arch Linux (7.2.7-book4) -
  test: el1-book4s" (`test-entry.sh add el1-book4s`: book4s, book4-sleep.dtb,
  the stick's EL1 arguments; not booted yet). The old "Arch Linux
  (7.2.7-book4)" entry has no logged boot since at least 19 October; its
  kernel and DTB are Fedora's and boot, so it stops in Arch's initramfs of
  10 October or right after it. Second stick test (4 November, ISO of 13:23): booted after a few
  bounces (not resets) at EL1: no `/dev/kvm`. A photo of the "second GRUB"
  shows the FIRST menu (full entries, 5 s countdown; grub-el2.cfg has only EL2
  entries and 1 s): the UEFI Shell chainloaded from GRUB returns at once, so
  GRUB re-shows its menu and retries (the morning's loop was likely the same
  thing). No key was pressed (only power held), so the boot that came up
  most likely went through grub-el2.efi's EL2 entry after one good round,
  yet ran at EL1: slbounce did not switch. Two faults then: the Shell
  returning (intermittent) and no Secure Launch. Agreed for the next ISO
  (not done yet): startup-live.nsh logs to `\book4-boot.log` on the stick
  (which fs, each `load`'s result, the second GRUB), and `write` adds a
  `BOOK4-LOG` partition where a live service keeps the journal and dmesg,
  so the whole boot can be read back from Arch. Next: let it bounce untouched,
  then `cat /proc/cmdline` (ecv=1 = EL2 entry) and `dmesg | grep 'started at EL'`; Next: from GRUB's console,
  `chainloader ($esp)/EFI/book4-el2/Shellaa64.efi` + `boot`, and see whether
  the Shell errors, runs startup.nsh and returns, or sits at `Shell>`; whether the EL2 entry was
  chosen and slbounce did not switch is unknown (next time: EL2 entry, then
  `/proc/cmdline` and `dmesg | grep 'started at EL'`); `book4-install`
  plan correct (keeps sda1-3, wipes sda4-5); the bar showed the battery at 0 %
  in the live session (not the battery, per the owner); the internal disk rebooted fine with the
  stick still in.
  A reset erases Fedora too, so before using it for real: back up both
  homes, and give the kernel tools a Fedora-less path (build environment,
  `/boot/book4`, `lib/book4-grub.sh` instead of Fedora's GRUB).
- **Awake resets at EL2** (22 and 29 October, 1 November; PMIC goes down,
  RTC resets to 2024-05-29, nothing logged; the third one froze the screen
  first, with Chrome open): `install/arch/crash-log.sh` keeps a text journal
  per boot in `/var/log/book4-live/` (worked: 30 s more than the journal,
  still no clue). Cause: the X1 DC ZVA + CL5 erratum,
  reproduced with `x1e-crash` on 1 November (TODO.md). Fixed by sleep-backport
  0043 (DZE off + DC ZVA emulation, CL5 kept) and 0044 (KVM guests:
  `HCR_EL2.TDZ`), running since 1 November: the reproducer survives on
  the host and gets SIGILL in the VM. Watch: no awake reset for a few
  days.
- **Speaker VI feedback** (optional): works on the right pair on the test
  branch `book4/7.2-sleep-spk` (boot entry `el2-spk`); left pair not
  captured. Notes in `~/src/qcaudio-re` (private).
- **Deep-sleep power** 0.9 W against ~0.2 W on other X1E laptops: candidate
  rails in [TODO.md](TODO.md).

## Hard rules

- **Boot:** keep `cutmem` and `cma=256M`. Never delete anything from the ESP.
  Keep `linux-modules-cleanup.service` masked while Arch has more than one
  kernel. Never run `omarchy-reinstall-configs`, `omarchy-refresh-limine`,
  `omarchy-setup-security-fingerprint` or Omarchy's `post-install/pacman.sh`.
- **Resets the machine:** reading `clk_summary` after LPASS powers down,
  unbinding `lpasscc-sc8280xp`, reading `0xAF20000` at EL1, stopping DSPs at
  EL2 (votes stay stuck), a hung NPU session (reboot at once; no NPU runs
  that can hang until dspsignal works).
- **Speakers:** never hand the gain to the amps' DRE (garbled output, one
  PMIC reset). Thermal at PA 23 is a non-issue (coils +3 °C).
- **Keep blacklisted:** `qcom_adsp_pwr_lmts` (crashes the ADSP on this
  machine; Samsung disables it on Windows too).
- **Privacy and publishing:** no personal data (MAC, IPs, SSIDs) in this
  repo; Windows/Samsung/Qualcomm binaries, decompiled code and ACDB data stay
  local; posting on GitHub, mailing upstream or force-pushing needs the
  owner's OK first. The live ISO is never uploaded.
- **Root:** the assistant has no sudo. Short commands go through `pkexec`
  (the owner approves); longer root work is a script in `~` that the owner
  runs as themself (`bash ~/x.sh`, sudo inside), never `sudo bash`.

## Where things are

- This repo: docs index in [README.md](../README.md); kernel fork
  n1c0la84/linux-book4-edge (sparse clone `~/src/linux-book4-edge`).
- Private, local only: `~/src/qcaudio-re` (speakers), `~/src/qcpep-re`,
  `~/src/qcsubsys-re`, `~/src/book4-acpi` (power), `~/src/el2-usb`,
  `~/src/ext` (qebspil, x1e-sleep), `~/src/slbounce`, `~/src/omarchy-build`,
  `~/src/book4-iso` (ISO work tree, ~14 GB; `live-iso.sh clean` deletes it, the next build copies the system again), `~/npu`.
- Scripts still in `~` and not in the repo (one-offs from the speaker work):
  `fix-crossover-volume.sh`, `install-woofer-highpass.sh`,
  `spk-test-prep.sh`, `spk-tplg-reload.sh`, `spk-vi-sweep.sh`,
  `vi-capture-test.sh`, `vi-debug*.sh`; `nas-mount.sh` (CIFS automount of the NAS share at `/mnt/storage`, credentials root-only in `/etc/samba/credentials/`, kept out of the ISO); older: `audio-modules-prep.sh`
  (obsolete), `npu-setup.sh`, `install-arch.sh`.

## Working protocol

1. Start: read this file and `git log --oneline -20`, then the doc of the
   topic at hand.
2. Everything that must survive goes into the repo (code, docs, this file),
   or is at least named here by path if it is private.
3. End: update this file (date, what changed), commit and push. Parallel
   sessions see each other through git: pull before editing.
