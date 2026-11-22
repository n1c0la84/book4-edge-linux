# State

**Start here: [ROADMAP.md](ROADMAP.md)** (17 November 2026): the single list of
what to do next and where it is heading (stock Omarchy plus a Book4 layer on
top), with the scripts, the kernel port analysis to Anatase's 7.3 and the
boot move from GRUB/Fedora to Limine.

**17 November 2026**: printing set up: HP ENVY Photo 6200 (192.168.178.9) as
driverless IPP Everywhere queue `HP_ENVY_6200` (`lpadmin -m everywhere`, dnssd
URI, A4, not shared), system default. Needs only cups + avahi + nss-mdns, all
already installed; no HP driver.
Scanning: `sane sane-airscan simple-scan` installed (eSCL over the network);
`escl` and `v4l` commented out in /etc/sane.d/dll.conf (duplicate entry; v4l
probed the camera and printed junk). If a job sits at "printing", check the
printer panel: it holds jobs until a low-ink alert is acknowledged
(`curl http://192.168.178.9/DevMgmt/ProductStatusDyn.xml`).
Scan to PDF: `~/.local/bin/scan [name] [dpi] [color|gray]` (private, A4 area,
300 dpi default, to ~/Documents/Scans); Document Scanner set to text mode,
300 dpi, PDF, same folder, HP preselected (gsettings org.gnome.SimpleScan).

**18 November 2026, later: videos would not open (mpv, no window).** Omarchy
4.5's migration ran `omarchy-install-video-decode` (11:17), which put
`hwdec=auto-safe,v4l2m2m-copy` in `~/.config/mpv/mpv.conf`. On el2-73 the
Iris decoder then faults on the first stream (SMMU SID 0x1940 at iova 0,
`qcom-iris: system error 0x5000003`, vb2_start_streaming WARN); mpv creates
its window but never presents a frame and ignores SIGTERM, so nothing shows.
First fault 12:39 (a 2832x1700 screen recording); after it Iris fails at every
size, 1080p included, until reboot. mpv.conf now has plain `hwdec=auto-safe`
(the Omarchy script keeps a global hwdec the user set); software decode plays
fine. Still to find: whether Iris fails from a fresh boot or only after the
first fault (`tools/video/iris-test.sh` after a reboot, then a 2832x1700 file).

**Updated 22 November 2026**: Replied on jglathe/linux_ms_dev_kit#102 (issuecomment-7079688959; jglathe credited our syscon fix, now in 7.3.3-jg-2): their T14s ADSP stuck awake in s2idle may be `qcom_adsp_pwr_lmts` crashing it (dead DSP at EL2 looks frozen in qcom_stats); our blacklist, the 7.3 LPASS va/wsa macro fix and our ~0.7 W EL2 numbers. Open: birkskyum (arewearmyet#10) asks for a run of Omarchy's kernel (linux-omarchy 7.3-75, edge) beside ours; side-by-side test entry "omarchy-el2" prepared, not installed yet (edge alsa-ucm-conf would collide with book4-edge's Samsung UCM files; hw-test not available on the stable channel).

**Updated 20 November 2026**: **[book4] online** (docs/packages-online.md): workflow `.github/workflows/packages.yml` (manual) builds linux-book4, book4-edge, book4-edge-boot and book4-edge-el2 on GitHub's arm64 runner in an Arch Linux ARM container (official rootfs, signature checked against keys/archlinuxarm-build-system.asc), signs with makepkg --sign and publishes a signed repository in the release `repo`. Signing key E75AAB6A080DCE59DC84259D595D834A7E98BBCE (ed25519, made in RAM, private part only in the secret BOOK4_SIGN_KEY, public in keys/book4-repo.asc). linux-book4's PKGBUILD pins `_commit` (book4/7.3 f1ea704) and falls back to packages/linux-book4/config (this machine's .config). Firmware never built there. Nothing changed on the laptop: it keeps the local [book4]. First publish 09:50 (run 44713389902, after three fixes: DisableSandbox, explicit mirror list, runner paths allowed in the home-path check since the upstream UEFI Shell carries one): book4-edge r581, book4-edge-boot r581, book4-edge-el2 -2; signatures checked from outside with keys/book4-repo.asc; the CI-built Shell, qebspil and slbounce are byte-identical to the installed ones. Kernel published 13:30 (run 44734722137, ~70 min build; signature checked from outside; same 5910 files as the installed linux-book4 7.3.4-3). The first two kernel runs built and signed fine but were stopped by the home-path check (upstream kernel files name developers' homes: BPF iterators skeleton, scripts in the headers); the check now reads only the build metadata (.BUILDINFO/.PKGINFO), where a local build shows /home/nicola. Local builds record that path, so publish only CI builds. All four public packages are now in the release `repo`.

**Updated 19 November 2026**: **Camera in Qt apps (Monologue):** Qt Multimedia 6.12 finds cameras only through V4L2, where this laptop has just the raw CAMSS nodes; the camera itself is a libcamera camera (PipeWire shows "Built-in Front Camera", so browsers and portal apps see it). `libcamerify` (libcamera's V4L2 compatibility layer) presents it as /dev/video0 with BGRA/BGRX up to 1920x1080 (a frame grabbed through ffmpeg). That did not help: Qt finds the camera through libcamerify but drops it (no frame intervals: "Camera does not support FrameDurationLimits"). Then `install/arch/camera-relay.sh` (v4l2-relayd + v4l2loopback "Book4 Camera", as Omarchy's Cam Link; the unit needed DeviceAllow for /dev/udmabuf and dma_heap, else no software ISP): the relay hands out a frozen frame (60 identical frames), while a plain `gst-launch libcamerasrc ! videoconvert ! NV12 ! v4l2sink` into the same loopback gives live video (58 of 60 frames distinct) and libcamerasrc alone runs at 41 fps. Relay parked (stopped, not started at boot) until solved; next idea: an on-demand relay of our own (start that gst pipeline on the loopback's client-usage event). Browsers use PipeWire's "Built-in Front Camera": Chromium already had --enable-features=WebRtcPipeWireCamera, Google Chrome did not (webcamtests failed); added to ~/.config/chrome-flags.conf; works (webcamtests), a bit washed out: libcamera has no ov02c10 tuning file and uses simple/uncalibrated.yaml (possible later: an ov02c10.yaml with a colour matrix, contrast and saturation). Bar after the packaging: the hw-monitor plugin enabled GPU load only for ~/.local/bin/book4-gpu-busy; its hw-probe (and userspace/desktop/hw-monitor-snapdragon.patch) now also accepts /usr/lib/book4/book4-gpu-busy. Plugin updated 1.1.1 -> 1.7.0 (our local changes had blocked the plugin manager); our changes rebased onto it (two conflicts: upstream's new temperature-only GPU dial kept, Apple SMC and Snapdragon tsens both kept), the repo patch regenerated against 1.7.0; old copy in ~/.config/omarchy/plugins-hw-monitor-1.1.1-patched.bak. OmaSettings removed from the bar and kept as a service plugin (shell.json "plugins"), so the launcher entry / `omarchy-shell omasettings toggle` still open it. **EL2 chain packaged and installed** (13:02, through [book4]: book4-edge-el2, book4-edge-boot r566, book4-edge-firmware -2 with tcblaunch; the 95-book4-el2 hook put the new slbounce.efi and startup.nsh on the ESP; `book4-el2 status` all current; first boot with everything packaged 13:05 OK: BootCurrent 0004, EL2 + KVM, el2-sleep helper (AOSD off, UFS held), all packaged units success, no failed units, Wi-Fi c5-00302, ADSP/CDSP attached, sound card and Speakers sink, fingerprints, Bluetooth; the boot-time audio messages (one APM CMD timeout, MultiMedia5 no backend) are in every earlier boot too): `packages/book4-edge-el2` (UEFI Shell 26H1 pinned; qebspil 8e4d9e6 and slbounce c090a8c built from upstream with our patches; startup.nsh, windows.nsh; `book4-el2 install|update|status` writes only \EFI\book4-el2-arch\ and \firmware\..., never deletes; hook 95-book4-el2 keeps the ESP current). Built: Shell and qebspil byte-identical to the ESP copies; slbounce differs (patch now also looks in \EFI\book4-el2-arch\, so a fresh install needs no \EFI\book4-el2\). tcblaunch.exe 10.0.26100.9616 joins book4-edge-firmware (from WinSxS by checksum; System32 is now 9882). windows.nsh moved from book4-edge-boot to the EL2 package. **Local pacman repository [book4]** written (`install/arch/book4-repo.sh setup`, not yet run): /var/lib/book4-repo (yours, never published), /etc/pacman.d/book4-repo.conf included at the end of /etc/pacman.conf (Omarchy migrations edit pacman.conf in place, so the Include survives); `book4-repo.sh add [NAME]` after a makepkg, then pacman -Syu / omarchy-update installs it. **Firmware packaged** (12:41): book4-edge-firmware 2026.11.19 installed (staged from Windows by checksum, install/arch/firmware-stage.sh; all of /usr/lib/firmware/updates now owned except the old tplg .bin.xz copy, superseded by the packaged .bin alias; delete it after a reboot with sound). **Book4 layer packaged** (afternoon): `packages/book4-edge` and `packages/book4-edge-boot` build (makepkg); `install/arch/book4-edge-migrate.sh` (run 12:33: both installed, 30 copies backed up and retired, units now from /usr/lib, hook rebuilt the initramfs with the blacklists and the menu) installs them and retires the script-installed copies (all 26 checked identical to the packaged files, two differ only in comments; backups to ~/book4-edge-migrated-*). Brought into the repo from the system: the EL2 sleep helper and unit (userspace/standby/book4-el2-sleep*), the pwrlmts and spss-nvm blacklists, the USB no-wake rule, the WirePlumber software-volume drop-in (90-book4-software-volume.conf, 30 Oct), the mkinitcpio drop-in. Not packaged on purpose: test/debug pieces (book4-modules-swap, book4-spk-test, emuec dyndbg, fastrpc rule, sshd drop-in). **Windows round trip (12:02-12:11):** fingerprints enrolled in Windows Hello and imported at the next Linux boot (left and right index; book4-fingerprint-import on arch-45). Two problems: (1) Arch GRUB 2.16 cannot chainload Windows (bootmgr: BCD 0xc00000bb; Fedora GRUB 2.12 could; suspect the device path GRUB gives the image on this 4K-sector disk); the GRUB entry now chainloads the UEFI Shell with windows.nsh (`arch-grub.sh windows`; untested), F10 meanwhile; lock screen uses the fingerprint by itself (pam omarchy-lock-fingerprint + fprintd-list); (2) Windows re-created its BCD copy of the old "Fedora" firmware entry (0002, \EFI\fedora\grubaa64.efi at EL1) and put it FIRST; at EL1 its default omarchy45 (EL2 DTB) hangs. Fix: BootOrder 0004,0003,0000,0002 (arch-grub.sh default no longer renames that entry), and in Windows `bcdedit /delete` its firmware object. Roadmap rewritten at the top (Status table, next steps, the owner's plan for a fresh install from the official ISO instead of Limine now: space, the 260 MB ESP, cutmem/DTB/EL2, package the layer first). **Windows shrunk, root grown to 196 GB (89 GB free)** (`install/arch/windows-shrink.sh`, 11:40-11:55; three restarts: chkdsk-flagged volume needs `ntfsresize --info --force`, this UFS disk has 4096-byte logical sectors so sfdisk counts in 4K units, partx -a on an already-added sda6). Table before: ~/sda-table-before-shrink.sfdisk. Boot Windows once (chkdsk scheduled). The root btrfs now spans sda5 + sda6 (devid 2, 74.5 GiB): any rescue/live system must see both. NTFS 380 -> 300 GB (264 GB used; ntfsresize dry run OK, 43 GB to relocate), sda3 shrunk in place (start/GUID kept), new sda6 (~80 GB) added to the root btrfs (`btrfs device add`; the initramfs systemd hook carries 64-btrfs.rules, so a two-device root assembles at boot). Iris from a fresh boot: 1080p h264/hevc decode clean (h264 hw 2.2 s vs sw 0.39 s, hevc 1.3 vs 1.7 s per 600 frames); the fault needs the 2832x1700 stream. **Unplug-during-sleep reset is back on 7.3, fix ported** (morning: charger out with the lid shut, hard reset, no log; Anatase's reworked samsung-emuec re-enables its interrupt at device resume instead of after every device has resumed). Ported our 0002 quiesce (PM notifier, PM_SUSPEND_PREPARE to PM_POST_SUSPEND) to book4/7.3 (8c90bfa97a), plus 0003 wake on plug-in into an empty port (f1ea704def); linux-book4 7.3.4-3. Checked 7.2-sleep against 7.3 by commit subject: nothing else missing (0001 PD retry covered by Anatase's rework; timer half-range and DSP attach present in other commits). Test: sleep with the charger in, unplug, wake; journal must show `samsung-emuec ... pm: quiesced (attached=1 wake=0)` / `pm: resumed, resync`. Screensaver turned off (`omarchy toggle screensaver`). **Verified** 10:28-10:29 (charger port 1-0033 `attached=1 wake=0`, empty port 3-0033 `wake=1`, unplugged with the lid shut, resumed on battery, no reset). **Part B: Arch GRUB boots** (first test boot via `arch-grub.sh next`, BootCurrent 0004: Shell + qebspil + slbounce + Arch GRUB 2.16 + 7.3.4-3, EL2, KVM, sleep service active). Normal boot is still 0003 (Fedora GRUB). B3 installed and booted (10:48 setup, test entries retitled; Arch GRUB boot via `next`: BootCurrent 0004, EL2, sleep service active, no failed units): `install/arch/book4-boot-setup.sh` installs book4-boot and its pacman hooks (plan-arch-boot.md B3); test entries get real titles (`test-entry.sh retitle`; they all said "Arch Linux (7.2.7-book4)"). B5 done 19 Nov (`arch-grub.sh default`; BootOrder 0004,0003,0001,0000): labels "Omarchy (EL2, Arch GRUB)", "Omarchy (EL2, Fedora GRUB, fallback)", "Fedora GRUB (EL1)", OpenBSD entry removed (files stay), order Arch GRUB first; the Arch startup.nsh falls back to Fedora GRUB; `/efi` gets an fstab automount (gpt-auto mounts the ESP only when Fedora GRUB booted: it sets LoaderDevicePartUUID, Arch GRUB does not). Back: `arch-grub.sh fedora-default`. EL1 entry still to try. **Part C started (retire, not delete):** archive done 11:17 (home 1.9 GB reflinked, 3487 files; both 7.2 .git copies fsck clean; dirty patch 69 files; disk unchanged at 15 GB free) by `install/arch/fedora-retire.sh archive` (Fedora home -> ~/fedora-archive reflinked; patchwork/patchwork-sleep .git copies plus dirty patch, 69 uncommitted files in patchwork-sleep = 7.2.7-book4s source; linux-73 branches -> refs/fedora/linux-73/*); diagnostic module builds now on Arch (`tools/power/build-module.sh`, 7 built on 7.3.4); docs/fedora-retired.md classifies every Fedora-using script.

**Updated 18 November 2026**: **The daily kernel is now the pacman package linux-book4 7.3.4-1, built on Arch** (packages/linux-book4, tools/kernel/install-book4-kernel.sh; plan A done). Kernel built on Arch as a pacman package works (linux-book4p test, nap 97.2 %; docs/plan-arch-boot.md A). Disk: deleted the snapshots arch-pre-omarchy-20261003-1109 and arch-pre-update-20261104-0934 and Fedora-home kernel trees patchwork-pdc, patchwork-ufs-qcom-lane-clks-guard, tweeters: 8.5 -> 22 GiB free (82 %). **el2-73 (7.3.4-book4) is now the daily kernel** (owner switched, 18 Nov; 7.2.7-book4s stays as the fallback entry). el2-73 rebuilt with both fixes: check clean, nap 96.6 %; daily switch after a long battery sleep and a few days of use. 7.3 audio fixed: reverting c663014e45 (audioreach channel maps) makes the mic record and the speakers play (book4/7.3 767f896; running as updates/ modules until rebuilt). 7.3 sleep blocker found: the CoreSight CTCU (new in 7.3's hamoa.dtsi) keeps the QDSS clock on; with it disabled 7.3 collapses (97 %). Fixed on book4/7.3 (f79c9d4); boot "test: 73-noctcu" until rebuilt. Mic broken on 7.3 (APM port 110). Earlier, 17 November: 7.3: no CX collapse in s2idle (ROADMAP 7a, suspect a600000.usb votes); 0040/0041/battery refresh ported, release name fixed, rebuild pending. el2-73 (7.3.4) first boot: works broadly; qcom_spss_nvm probe loop blacklisted (/etc/modprobe.d/book4-spss-nvm.conf), Iris needs 0040 ported (ROADMAP 7a). Speakers: swr0 is the LEFT side (one amp at a time, phone at each slit); our woofer renaming was wrong, fixed on book4/7.3 (555bdfe16f), corrections posted to omarchy#15860 and kernel-anatase#1; the daily 7.2 overlays still carry the old names. Performance note (memlat, boost, capacities, 95 C trip) posted to birkskyum. Omarchy's nightly image boots on the 14" to the installer (no Wi-Fi/GPU/audio firmware in it; reported). Anatase reworked the Samsung drivers; our remaining changes sent (kernel-anatase#1). Roadmap in ROADMAP.md. Earlier, 16 November: Added `install/arch/gparted-hidpi.sh`: GParted
needs `xorg-xhost` under Wayland to open (`sudo pacman -S xorg-xhost`), and its
root GTK process loses the user's `GDK_SCALE=2`; running the script installs a
root-only GTK3 22-point font setting for readable GParted text. **Windows
standby on battery measured: 0.11 W** over 570 min (sleep study; Linux 0.70-0.84 W), so ~0.6 W of board power is still to find (TODO.md, board power item). Earlier:: CL5/DRIPS comparison measured (EL2, book4s
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
97.4 % and no timer module; both reported in omarchy#15860
(discussioncomment-19601392), with the UFS-on-resume caveat and, added
14 November, that linux-omarchy's ADSP standby message (2176) crashes
this ADSP. **Night of 13-14 November: `deep` at EL1, 631 min on
battery, 0.84 W, `cxsd` 100 %, clean resume** (not reported yet). In
that night CX came up ten times with APSS down throughout, about hourly
(the last at 11 h + 5 s of the AOP's clock), possibly the event behind
the hourly AOSD resets. With the Secure Processor stopped
(`tools/experiments/spss-stop.sh`, 11:04) a 273 min sleep on the same
boot had a single CX entry, no visit at all (0.80 W, `cxsd` 100 %): **the
Secure Processor is the hourly visitor**, confirmed from the other side
after the reboot (EL2, s2idle: 122 min, visits at 1 h and 2 h + 5 s of the
AOP clock). **It is not the cause of the hourly AOSD reset:** at EL2 in
s2idle with it stopped and AOSD allowed, the machine power-cycled at the
3 h mark of the AOP clock + ~70 s, 45 min into the sleep, RTC back at
2024-05-29. Both follow the same hourly tick of the always-on side. AOSD
stays off, SPSS stays running (TODO.md, "Why AOSD resets"). (At EL1 in
deep the same attempt reset after ~55 s with the RTC intact: a different
failure.) **15 November: the stock-image condition (EL1, deep, AOSD
allowed, SPSS running) lost the disk on resume** (btrfs errors, power
held; filesystem clean afterwards): on this laptop AOSD has to stay off
in every setup tried (reported in omarchy#15860). Lead for the EL2 hourly
reset: it is reported only with qebspil-started DSPs; a Surface Pro 11 at
EL2 with Linux-started DSPs (x1e-dsp) ran AOSD 73 min without it. At EL1
in s2idle AOSD worked for the first sleep of a boot (92.8 %, UFS fine)
and then blocked every collapse (152 min at 2.00 W) until switched off
again. AOSD stays off everywhere. The kernel's own switch
(`qcom_aoss` debugfs `prevent_aoss_sleep`, Y or N) does not turn it off
here, only the `val:` form aoss_cxsd_only sends (reported in omarchy#15860,
discussioncomment-19640176: linux-omarchy needs that message for the 14").
birkskyum will carry a `qcom_aoss` patch (format fix + kernel parameter
sending the `val:` form) and send the format fix to linux-arm-msm with our
table; credit agreed 16 November (discussioncomment-19655186, address = the
commit address, not written in the thread). To do: test his kernel when posted.
The
sleep log now records CX entries per sleep (installed 14 November). The CNTV
arming is now a kernel patch, sleep-backport 0045 (written, not built or
tested; parked, the build would replace the daily kernel). Instead: a
reply on Burch's linux-arm-msm thread with the finding, drafted in
`docs/drafts/` for the owner to send. Next (plan in TODO.md): the blog post's EL1
claim, the VM check, a Windows
battery-standby figure for the ~0.7 W, the Omarchy edge image with one
suspend. Boot entries tidied 15 November: `el2-sleep` (default),
`el1-sleep`, `el2-spk`, `el2-nomisc` remain. Still pending: the Omarchy edge image boot test (live only) when
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
