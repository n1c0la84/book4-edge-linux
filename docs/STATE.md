# State

**Updated 31 October 2026.** The one page to read at the start of every
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

Not working: external monitor over USB-C (AUX timeouts); NPU inference
(dspqueue hang; dspsignal port 0041 written, untested).

## In progress

- **Live ISO and reset installer** (29-30 October,
  [install.md](install.md#undo-and-recovery)): `install/arch/live-iso.sh`
  builds `~/book4-live.iso` (private: tcblaunch.exe and Windows firmware
  inside), never booted yet. Next: write a stick, boot EL2 then EL1, run
  `sudo book4-install` (plan only) and review it before any `--wipe`.
  A reset erases Fedora too, so before using it for real: back up both
  homes, and give the kernel tools a Fedora-less path (build environment,
  `/boot/book4`, `lib/book4-grub.sh` instead of Fedora's GRUB).
- **Awake resets at EL2** (22 and 29 October, PMIC goes down, nothing
  logged): `install/arch/crash-log.sh` now keeps a text journal per boot in
  `/var/log/book4-live/`. Next: reproduce with LightCraft on battery.
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
  `~/src/book4-iso` (ISO work tree), `~/npu`.
- Scripts still in `~` and not in the repo (one-offs from the speaker work):
  `fix-crossover-volume.sh`, `install-woofer-highpass.sh`,
  `spk-test-prep.sh`, `spk-tplg-reload.sh`, `spk-vi-sweep.sh`,
  `vi-capture-test.sh`, `vi-debug*.sh`; older: `audio-modules-prep.sh`
  (obsolete), `npu-setup.sh`, `install-arch.sh`.

## Working protocol

1. Start: read this file and `git log --oneline -20`, then the doc of the
   topic at hand.
2. Everything that must survive goes into the repo (code, docs, this file),
   or is at least named here by path if it is private.
3. End: update this file (date, what changed), commit and push. Parallel
   sessions see each other through git: pull before editing.
