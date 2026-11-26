# State

**Start here: [ROADMAP.md](ROADMAP.md)** (17 November 2026): the single list of
what to do next and where it is heading (stock Omarchy plus a Book4 layer on
top), with the scripts, the kernel port analysis to Anatase's 7.3 and the
boot move from GRUB/Fedora to Limine.

**26 November 2026, 15:25: documentation refresh, provenance update and lint CI.**
Rewrote `README.md`, `docs/install.md`, `docs/updates.md` and the bottom
summary of `docs/STATE.md` to match the current Arch/Omarchy 4.5 + Limine/UKI
+ `linux-book4` 7.3.4 + signed `[book4]` setup (retiring Fedora/GRUB/7.2
contradictions across `ROADMAP.md`, `sensors.md`, `firmware.md`, `power.md`,
`camera.md`, `fedora-retired.md`, `plan-limine.md`, `plan-arch-boot.md` and
topic docs). Updated `CREDITS.md` (Rafael Meneses / `SB4-Edge-Linux`,
`sleep-backport` `0029–0045`, `UEFI-Shell`, `fastrpc`, `libssc`,
`iio-sensor-proxy`, `libfprint` MR !547, community contributors) and `LICENSE`.
Redacted home LAN IPs, personal email/usernames from `STATE.md` and handoff
docs per the privacy rule. Added `.claude/` to `.gitignore` and added
`.github/workflows/lint.yml` (`bash -n`, Python AST + `unittest`, `dtc`
overlay compile check, YAML check).

**26 November 2026, 15:15: packaging and fresh-install fixes.**
`packages/book4-edge`: added missing runtime `depends` (`swh-plugins`,
`pipewire-audio`, `bluez-utils`, `kmod`, `util-linux`, `python`) and `fprintd`
in `optdepends`, switched to `arch=(any)`, and packaged
`app-slice-oomd.conf`. `packages/book4-edge-boot`: added `python-pefile` to
`optdepends` and added `usr/share/book4/x1-el2-book4.dtso` and
`etc/mkinitcpio.conf.d/*` triggers to `91-book4-boot.hook`.
`packages/linux-book4`: added `git` to `makedepends`, fixed `_package_headers`
so required files fail loudly if missing and broken-symlink cleanup is not
cut short by `head -3`. `packages/libssc-book4`: added `gobject-introspection`
and `protobuf` to `makedepends` (eliminates CI-vs-local `.gir`/`.typelib`
drift), pinned patch sha256sum, made `prepare()` idempotent.
`packages/iio-sensor-proxy-book4`: pinned patch sha512sum, made `prepare()`
idempotent. `packages/book4-sensors`: dropped "(experimental)" and added a
`post_install` hint for `book4-autobrightness`. Moved `libfprint-sdcp` from
`userspace/fingerprint/arch/PKGBUILD` into `packages/libfprint-sdcp/` and
added it to CI (`packages.yml`, `build-packages.sh`) and `book4-repo.sh`
(along with the four sensor packages). `install/arch/firmware-stage.sh`:
fixed `sudo sha256sum "$c"` redirection, `BOOK4_WIN_DEV`, trap ordering, and
added `BOOK4_FW_LOCAL` + `/usr/lib/firmware/$path` fallback so `gen70500_sqe.fw`
stages automatically on a fresh install and c5-00302 Wi-Fi files can be supplied
from a backup dir. `book4-edge-migrate.sh`: filtered `.sig` files. Updated
`docs/packages-online.md`.

**26 November 2026, 15:00: CI signing/publish hardening and backup script updated.**
`.github/scripts/build-packages.sh` now imports `BOOK4_SIGN_KEY` into a
root-only keyring and unsets it before any `makepkg` build runs as `builder`
(builds unsigned, checks `.BUILDINFO`/`.PKGINFO`, then signs packages and
runs `repo-add` as root; `builder` only owns `packages/`). `.github/workflows/packages.yml`
only skips `gh release download` when the `repo` release has 0 assets (no
`|| true`, so a transient download error cannot wipe existing packages on a
partial build), disables globbing for `$PKGS`, and uploads `*.pkg.tar.*`
before `book4.{db,files}*`. `tools/backup/linux-backup.sh` updated for the
post-23-Nov layout: detects the running btrfs subvolume (`arch-45`, failing
if missing instead of silently skipping deleted `root`/`home`/`arch`), backs
up Limine's `/boot` (`sda7` `BOOK4ESP`) and fallback GRUB `/boot` (`sda4`),
archives all Linux/EL2 directories plus `firmware/` from `sda1`, and saves
`efibootmgr -v`. Not yet run live on an external drive or CI workflow.

**26 November 2026, 13:00: resume health check and drain logger installed**
(book4-edge r685.8ed440e). `book4-resume-check` (system-sleep hook; runs
15 s after every resume, also after a failed suspend, through a transient
timer): fingerprint reader (1c7a) missing -> rebind a200000.usb; fprintd
log since the resume shows an assertion / "already claimed" / claim
failure (or the reader was rebound) -> kill and restart fprintd;
adsprpcd >= 20 retries since the resume -> stop book4-sensors (a restart
does not help; reboot restores it). One line per resume in
`journalctl -t book4-resume-check`, a notification only when it repaired
something. Dry runs on today's journal: flags the 12:48 fprintd wedge and
the overnight adsprpcd loop, "ok" on a clean window. Not yet seen live.
`book4-drain` (user service book4-drain, enabled): one CSV row a minute in
~/.local/state/book4-drain/drain-YYYY-MM.csv (avg/min/max W from the EC's
current x voltage sampled every 5 s, capacity, brightness, kbd backlight,
eDP DPMS, CPU % of one core, mean CPU MHz, GPU % from book4-gpu-busy,
Wi-Fi, top 3 processes by name); `book4-drain report [DAYS]` (battery
only: by screen brightness band, by CPU use, top CPU users in core-hours),
`book4-drain now` (10 s sample). First look, 12:57: 8.0 W at brightness
38 %, CPU 47 % of one core, mean 975 MHz, GPU 10 %.
First live resume check (13:02:11, lid 13:00:53-13:01:48): "ok". That
resume took 2.4 s (resume devices): the USB-C port with the hub and USB stick
(a600000.usb, QMP combo PHY fd5000) failed to resume (`phy initialization
timed-out`, `dwc3_qcom_pm_resume returns -110`, clk WARNING
`gcc_usb3_prim_phy_pipe_clk already disabled` in qmp_combo_usb_power_on);
the stick (USB 2) re-enumerated and works. Owner saw the touchpad pointer
frozen for a moment after opening; no i2c-hid or input error in the log.
book4-drain r687: a minute that spans a suspend is dropped (wall clock vs
monotonic gap > 5 s).
13:13: no sound: SoundWire clash at 13:02:21 after that resume, all four
WSA amps UNATTACHED, playback fails -61. Amp rebind impossible (wsa883x
has no bind/unbind), see TODO.md "SoundWire clash". Controller rebind
(6ab0000, 6b10000) tried at the owner's request: removed the sound card,
re-probe failed (IRQ type mismatch); reboot needed.
Upstream bug report drafts (not sent; owner reviews, checklist at the end
of each): docs/upstream-drafts/2026-11-soundwire-clash.txt (clash, wsa883x
not rebindable, qcom_swrm_remove IRQ race and re-probe IRQ type mismatch)
and docs/upstream-drafts/2026-11-usb-resume.txt (xHCI death on usb_2, QMP
combo PHY init timeout with the pipe-clock unwind warnings). Both need a
retest on an untainted kernel first.

**26 November 2026, 12:48: fingerprint unavailable on the lock screen after
a resume** (reader present on the bus). The fprintd-resume hook
(`/usr/lib/systemd/system-sleep/fprintd-resume`, unowned, restarts fprintd
after every resume) restarted it at 12:47:59; the lock screen's PAM claimed
at 12:48:01.25 while the reader was being reset (`usb 1-1: reset` 12:48:00.1
and 12:48:01.4); at 12:48:01.5 `fpi_sdcp_device_connect_complete: assertion
'priv->host_private_key' failed` (libfprint-sdcp, MR !547), the claim
hung (lock: `fingerprint-reach-timeout`) and later claims got `Device was
already claimed`. First such assertion in the last four boots (the 12:29
resume unlocked by finger). `systemctl restart fprintd` (12:5x) cleared it;
the old one only died on the stop timeout. Suspect: the restart racing the
lock screen's immediate claim and the reader's reset after resume.

**26 November 2026, 12:30: after a reboot (12:23) sleep works again.**
Lid closed 12:25:20-12:29:34 on battery: one suspend (no retries), 253 s,
cxsd 249 s (98.5 %), ddr 99.6 %, 7 CX entries; resume devices 1.3 s; the
fingerprint reader (usb 1-1) survived, ADSP and CDSP attached, no
adsprpcd loop. Charge unchanged over 4 min (EC step), so no wattage. Still
`qcom-pcie 1c08000.pcie: Timeout waiting for L2 entry` (Wi-Fi) on resume,
harmless here, also present before the xhci death. Wi-Fi back 15.0 s after
wake (12:29:35 -> CONNECTED_GLOBAL 12:29:50): ath12k reloads its firmware
on resume and the driver hints regdomain US; 5.6 s later IT (from the AP);
NM auto-activates only at +12.2 s (first scan with the new channel list,
6 GHz enabled); auth+assoc 0.27 s, DHCP 2.2 s. Same on earlier real
resumes: 12.7-14.9 s (23-25 Nov). This time it joined 2.4 GHz (ch 5,
...a7) instead of the 5 GHz BSSID (...a8) used before.
Tried 12:37 and reverted (both removed): (1) `cfg80211
ieee80211_regdom=IT` took (global IT) but the ath12k phy is
`self-managed`, so it ignores it and still starts on its own hint US after
each firmware load (boot: US, IT 5.5 s later, as before); (2) a cloned NM
profile with `band a` and priority 10 never connected: wpa_supplicant
scanned 18 s and NM failed it with `ssid-not-found`, although the three
APs' 5 GHz BSSIDs (ch 36) are visible and the original profile has joined
...a8 on 5 GHz before. The 2.4/5 GHz choice stays with wpa_supplicant.

**26 November 2026: awake drain measured; sleep broken this boot (xhci).**
UPower charge history, 19-26 Nov, awake on battery only (gaps > 15 min
dropped): 27.5 h, 395 % of 49.7 Wh, **7.1 W average** (segments 5.5-11 W,
most 6.5-8 W) = ~7 h from full; at the moment 6-9 W at brightness 640/2047,
balanced. Windows-class light use on this SoC is ~4-5 W, so the awake
budget, not s2idle, is where the hours are. Found while looking: since the
22:27 boot of 25 Nov every suspend fails (2991 attempts, ~every 30 s with
the lid closed, overnight and 09:19-11:57): `dwc3-qcom a800000.usb: port-1
HS-PHY not in L2`, then `xhci-hcd.1.auto ... platform_pm_suspend returns
-22`. Lid closed in that loop drained 3.2 W (vs ~0.7 W real sleep). The same
message appeared 8 times on boot -5 without blocking every sleep.
Cause narrowed: on internal bus 1 (xhci-hcd.1, the EGIS ETU905A80-E fingerprint
reader, 1c7a:05a1) the reader normally drops and re-enumerates on every
resume (24 and 25 Nov: `USB disconnect` then `new high-speed USB device`
in the same second). At 22:28:38 (first resume, 25 s after boot, charger
plugged in during it) it dropped and never came back; every suspend since
fails on that controller. Kernel log of that resume: `xhci-hcd.1.auto:
Abort failed to stop command ring: -110`, `xHCI host controller not
responding, assume dead`, `HC died`, resume took 15.75 s (suspend_test
WARNING). The same resume had `qcom-pcie 1c08000.pcie: Timeout waiting for
L2 entry` (Wi-Fi). Not the SDDM greeter (its PAM has no fprintd;
fprintd was not running). Recovery, verified 12:13 26 Nov: rebind the controller,
`echo a200000.usb > /sys/bus/platform/drivers/dwc3-qcom/unbind; sleep 1;
echo a200000.usb > /sys/bus/platform/drivers/dwc3-qcom/bind` (root); the
reader re-enumerates within 1 s.
book4-ec-standby hook inert (daily DTB). Also `adsprpcd sensorspd adsp`
restarts every 100 ms (`remote_init ... No space left on device`, ~10
log lines/s, 15 min CPU in 13.5 h). Cause: a side effect of the suspend
storm, not of the sensor setup: at 23:00:40, in one of the failed suspends
(user space frozen mid-call), the DSP call returned 0x8000042f, the
listener thread exited, and adsprpcd's in-process restart (every 100 ms)
cannot reattach (ENOSPC). The daily kernel's fastrpc.c returns -ENOSPC
only at probe ("too many sessions"), so at runtime it is most likely the
ADSP's own answer passed through: its sensorspd is still running (the
sensor reads) and still bound to the dead session, so a new attach is
refused. Not seen on earlier boots. The sensor keeps working
(monitor-sensor 153 lux at 12:2x): the PD runs, only its file service is
gone, so a registry write would now fail (the firmware asserts if it
can't write, taking the ADSP and sound down). A service
restart (12:16) does NOT clear it: the new process loops the same way from
its first try, so the session is not freed by the process exit; only a
reboot. Also found: the CDSP crashed at 22:29:20 25 Nov
(`sleep_statsi.c:537`, as on 25 Nov 10:11), during the first failed
suspends, stays down at EL2 until reboot; lasting fix
to do: make adsprpcd exit after N failed restarts so systemd restarts it
cleanly.

**25 November 2026, 15:00: slow charging on 7.3 fixed (kernel built, not installed).**
Charging at 11 % was ~5 W (0.34 A at 14.9 V): the 65 W charger, plugged in
while awake (14:46), was left at `PD contract 5000 mV 3000 mA (PDO 1)`.
emuec had requested PDO 5 (RDO 0x53051545), the TX bit cleared, the active
RDO stayed PDO 1, and the 7.3 driver's duplicate check never sent the
request again (7.2 had `drivers/anatase/patches/0001`, the retry, which the
7.3 port does not carry). The 29 October input-limit fix itself is in 7.3
as antheas' version (0x90/0x91 from the AC supply's external_power_changed,
silent on success), so the old patches-galaxybook-ec/0002 and patches/0005
are not needed there. Fix: book4/7.3 fabd94f46778 "samsung-emuec: repeat a
PD request the source did not take" (resend 1 s apart, up to 5 times,
logged as `PD request … not taken … retry N`). Tested by loading the
module by hand (14:52): 20 V / 3.25 A within 1 s, battery 1.48 A at 15.2 V
(~22 W); the retry itself was not needed on that reprobe, so it is still to
be seen on a real hot plug. linux-book4 7.3.4-4 built locally
(PKGBUILD `_commit` bumped); install with
`bash tools/kernel/install-book4-kernel.sh book4` (book4-boot's hook refreshes Limine), then reboot.

**25 November 2026: EC standby test prepared (for tonight, not run).**
`tools/power/ec-standby-test.sh` (run as the owner: `setup`, `status`,
`undo`) gives the EC the Modern Standby inputs Windows' firmware gives it,
together: GPIO 44 MODS low + GPIO 49 HPDC high while asleep (hook
`book4-ec-standby`, values held by a daemonized gpioset through the sleep).
Test UKI `/boot/EFI/Linux/book4-ecstandby-el2.efi` = the daily EL2 UKI with
GPIO 44 freed (`<35 1>, <45 3>`), Limine entry "EC standby test, MODS +
HPDC" through limine-extra.conf (daily stays default); the hook is inert on
the daily DTB. Sleeps are logged `[el2-mods+hpdc]` (book4-sleep-log now also
tags on /run/book4-ec-standby; setup installs the repo copy). LDOS is
already 0 here. **RESP dropped:** EC2.sys's MCU1 handler only logs and
stores it (0x140001f60, ctx+476, read nowhere; fedora-archive/home/book4-ec/
EC2.ann:949), so it never reaches the EC. Baseline 0.70 W (el2-sleep).

**25 November 2026: s2idle rails vs the Slim 5x (read-only check, nothing changed).**
Slim 5x (jglathe/linux_ms_dev_kit PR #109) went 1.2 -> 0.244 W at EL2 mostly by
dropping `regulator-always-on` from VREG_EDP_3P3 (~0.9 W). We already did the
same on 19 Oct (linux-book4 ec97fe5588ac, OCTA_VDD -> DISPLAY_VDD -> EDP_3P3
chain; live DT confirms no always-on), so our ~0.7 W is after that fix.
Always-on rails here vs Slim 5x: same MISC_3P3 (touchscreen), vph_pwr,
l12b, l15b; extra here: VREG_WCN_3P3 (Slim 5x lets pwrseq switch it; Wi-Fi
stays powered in s2idle anyway) and l7b_2p8 + l10b_1p8 in HPM, the ov02c10
camera's avdd/dvdd/dovdd (upstream DT, be19068f31ec; few mW at most). Slim 5x
has a switchable VREG_NVME_3P3 (GPIO 18); we have no NVMe rail in the DT.
No big Linux-visible always-on rail left: the remaining excess is likely
EC-controlled or a device in a higher state (NVMe, WCN, USB-C retimers).

**25 November 2026, 11:00: "dirty" speaker sound fixed (PipeWire resyncs).**
The speaker PCM followed the mic, which the echo canceller (book4-mic-ns.conf,
16 Nov) joins to every playback, at quantum 256 (480 rounded down to a power
of two); the DSP moves the speaker in fixed 480-frame periods, so its fill
swung ~±485 and PipeWire logged `follower ... resync` every ~2 s with hundreds
suppressed (199 lines in 22 min this boot). Fix: `book4-clock.conf` (min
quantum 480, no power-of-two rounding) and `api.alsa.htimestamp = true` on the
Speaker sink (book4-speakers-wireplumber.conf): 0 resyncs in 6 min, mic filter
clean. Dead ends: the speaker as driver (priority.driver 2000) stalls, hw_ptr
stays 0; period-size 240 is refused (stays 480); quantum 960 broke the echo
canceller. Also: **rtkit was not installed**, PipeWire ran without realtime
(threads SCHED_OTHER); installed, now RR 20, and book4-edge depends on it.
Check: `journalctl --user -u pipewire | grep -c resync`.

**25 November 2026, 10:20: automatic brightness on.** New user service
`book4-autobrightness` in book4-sensors r666.9411678 (userspace/sensors;
docs/sensors.md, "Automatic brightness"): claims the light sensor on
iio-sensor-proxy, log curve lux->percent (0:5, 10:20, 100:38, 1000:70,
10000:100), smoothing 0.3/sample, 3 % dead zone, 1 % steps every 40 ms via
logind SetBrightness; a brightness set by hand becomes a saved offset
(~/.local/state/book4-autobrightness/offset, now -2 %); skips while eDP DPMS
is off. Needs a 1 s backlight check, since iio-sensor-proxy only signals
changed values (first try missed manual changes). Tested: manual 60 %/40 %
learned as +18/-2 %, ramp 40->63->41 % in under a second each. Enabled for
the user (`systemctl --user enable --now book4-autobrightness`). Installing
r666 with only the real units running: no adsprpcd retry, ADSP and CDSP
attached.

**25 November 2026, 10:00: ambient light sensor works at EL1** (Limine
"Omarchy (7.3.4-book4) - EL1"). book4-sensors.service started by itself at
boot (udev rule); adsprpcd sensorspd read the registry and the 14"'s
`veml3328_0.json` from /vendor; only misses: `sns_tppe.so` and
`c:/Data/test/cam_registry_dump.txt` (both optional). ADSP stayed running.
`LIBSSC_LIGHT_DATA_TYPE=color ssccli --sensor light` (output only shows with a
tty or `-v`; piped it is buffered): ~91 lux every second, value[1] ~3955
(probably colour temperature, K). iio-sensor-proxy: HasAmbientLight true,
unit lux; `monitor-sensor --light` 91-93 lux (LightLevel reads 0 until a
client claims the sensor). Owner checked the response: 0 lux when covered, a
jump with a phone torch. **EL2 test (10:08, transient units, guard
bypassed): works** (ssccli ~106 lux, monitor-sensor 110-112 lux, ADSP attached,
four amps Attached, owner confirmed audio). Guard removed (book4-sensors
r663.3a83ca6). **But:** installing it reloaded udev and started the real units
while the test units still ran: the second adsprpcd sensorspd failed ~37 times
(listener register error, a session opened and closed each time) for 14 s;
the test units were stopped at 10:11:08 and at 10:11:09 the **CDSP** crashed
(`fatal error received: sleep_statsi.c:537`), the first CDSP crash in the
journal since 10 Nov; at EL2 it stays down until reboot. Sensor (115-120 lux),
ADSP and audio unaffected; bus-4 amps showed UNATTACHED while idle and
Attached during playback (idle state, not the stuck case). **Reboot at EL2 (10:14): clean.** The units
started at boot (udev rule), no listener retry loop, ADSP and CDSP attached
(no crash 48 s after the service started; the earlier one came after 15 s),
monitor-sensor 134-135 lux, four amps Attached. Guard removal kept: the light
sensor is on in daily use. The CDSP crash is put down to the two-daemon swap;
watch for a repeat. Next: auto-brightness. Was: the same at EL2 (the units are guarded off at EL2: a crashed ADSP stays down
there until reboot); then auto-brightness.

**25 November 2026: the tsens fix is ready to test on linux-omarchy 7.3-79.**
birkskyum (arewearmyet#10) confirmed the `qcom_tsens` crash; Christian
Schmidbauer's fix (lore 20261104145740.2623473-1-opensource@grische.xyz) is in
Omarchy's 7.3-79 on edge. Checked in the package: `init_common`,
`init_tsens_v{1,2}_no_rpm` and the v0_1/v1 `init_*` are in `.text` in
qcom_tsens.ko (they were in `.init.text` in 7.3-78). `omarchy-kernel-test.sh`
has a new switch `OMARCHY_TEST_TSENS=1` that keeps `qcom_tsens` in the
initramfs, as stock Omarchy has it, and checks that it is there. To run:
`OMARCHY_TEST_TSENS=1 OMARCHY_TEST_DEBUG=1 bash install/arch/omarchy-kernel-test.sh setup --yes`,
then the EL1 stock DTB entry. **Result (25 Nov): it boots.** EL1 stock-DTB
entry with earlycon: qcom_tsens.ko.zst in the initramfs, all four controllers
(c271000-c274000) bound, every thermal zone reading 42-45 C, no oops, no
WARNING/BUG. DT compatible `qcom,x1e80100-tsens`, `qcom,tsens-v2`, so this
exercises patch 1 (`init_common`); patch 2's per-SoC callbacks are not used on
X1E. Christian's cover letter listed `CONFIG_QCOM_TSENS=m` on hardware as
untested. Side note: every `?`-marked module in Omarchy's Qualcomm list logs
"Failed to find module 'x?'" from systemd-modules-load in the initramfs
(mkinitcpio's systemd hook writes MODULES with the `?` into
/etc/modules-load.d/MODULES.conf); harmless, udev loads them by modalias.
**Sent 25 Nov:** Tested-by as a reply to the cover letter (git send-email;
mail file `.git/upstream-mail/tsens-tested-by.eml`, not committed) and the
result on #10 (issuecomment-7157487373). `git send-email` is configured in
`~/.gitconfig` (`perl-authen-sasl` + `perl-io-socket-ssl`). On lore in the
thread (5 messages), under the cover letter, at 08:46 UTC. Next: wait for
Christian/Daniel; a v2 would need the Tested-by carried or re-given.

**24 November 2026, afternoon: no sound, recovered without a reboot.** The
SoundWire clash at playback (TODO.md, "SoundWire clash at the first playback")
came back on the 23 Nov Limine boot after ~23 h: clashes 15:38-16:14, PipeWire
links failed, the YouTube Music player stayed paused. Unlike 23 Nov, all four
WSA amps returned to `Attached` on their own; unpausing played. Not fixed;
check `cat /sys/bus/soundwire/devices/sdw:[14]*/status` first next time
(`Alert` = the stuck case, reboot).

**24 November 2026**: controlling the Mac mini from here: the Mac's own Screen
Sharing (VNC on 5900; Apple login type 30) with `remmina` + `libvncserver`
installed here. Profiles in `~/.local/share/remmina/` (LAN and Tailscale,
private); launcher entry `~/.local/share/applications/macmini-remote.desktop`
("Mac mini"). Remmina prefs: toolbar and single-tab strip hidden. Host key is
Right Ctrl (alone: keyboard grab so Super reaches the Mac as Cmd; +F fullscreen;
+T toolbar). Gliff (Omarchy's remote desktop, installed) is Hyprland-to-Hyprland
only. If VNC is too choppy: Sunshine on the Mac + the moonlight-qt already here.

**17 November 2026**: printing set up: HP ENVY Photo 6200 on the LAN as
driverless IPP Everywhere queue `HP_ENVY_6200` (`lpadmin -m everywhere`, dnssd
URI, A4, not shared), system default. Needs only cups + avahi + nss-mdns, all
already installed; no HP driver.
Scanning: `sane sane-airscan simple-scan` installed (eSCL over the network);
`escl` and `v4l` commented out in `/etc/sane.d/dll.conf` (duplicate entry; v4l
probed the camera and printed junk). If a job sits at "printing", check the
printer panel: it holds jobs until a low-ink alert is acknowledged
(`/DevMgmt/ProductStatusDyn.xml`).
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

**Updated 23 November 2026**: **Online [book4] gets the four new public packages** (fastrpc, libssc-book4, iio-sensor-proxy-book4, book4-sensors; build-packages.sh allowlist, book4-sensors built with -d since book4-edge-firmware is never online); run 45211790953 succeeded, online db now 9 packages. Then rebuilt online (run 45212506973): book4-edge-boot r653 (with the Limine side), book4-edge-el2 2026.11.19-5. **Private [book4-private] on the Unraid share** (`install/arch/book4-private.sh publish|list|install`, /mnt/storage/BACKUPS/book4-private): book4-edge-firmware 2026.11.23-1 stored; not in pacman.conf (unreachable away from home would break -Syu). **Ambient light sensor, step 1 (packages built, in local [book4], not installed):** `packages/fastrpc` (quic/fastrpc 89508ea, Rafael's pin; adsprpcd/cdsprpcd and libs only, no udev rules or units, so nothing auto-starts cdsprpcd), `packages/libssc-book4` (Arch's libssc 0.4.4 + Rafael's LIBSSC_LIGHT_DATA_TYPE patch: the VEML3328 is published as data type "color", stock libssc looks for "ambient_light"; replaces libssc), `packages/iio-sensor-proxy-book4` (3.9, -Dssc-support=enabled, + Rafael's client_vanished fix; replaces iio-sensor-proxy). Arch extra already has libssc 0.4.4 and iio-sensor-proxy 3.9 with SSC. Patches from github.com/rafaelmnz/SB4-Edge-Linux (GPL-2.0). **Step 2 (23 Nov):** the 14"'s files found in Windows: config in DriverStore `qcsensorsconfigcrd8380.inf_arm64_*` (37 JSON incl. `8380_ss_nx14_veml3328_0.json`, json.lst, sns_reg_config, 6 socinfo files: soc_id 555, CRD, rev 3.1; config mtime 1719257058), generated registry in `System32/drivers/DriverData/Qualcomm/fastRPC/persist/sensors/registry` (111 files + sns_reg_version); 157 checksum lines added to book4-edge-firmware (2026.11.23, new `driverdata:` source in firmware-stage.sh), files stay local, installed to /usr/share/book4/sensors. New package `book4-sensors` (userspace/sensors: setup script after Rafael's, adsprpcd sensorspd service, /vendor tmpfiles link, udev rule, iio-sensor-proxy drop-in with LIBSSC_LIGHT_DATA_TYPE=color); nothing enabled, service and rule inert at EL2 (/dev/kvm). Installed 16:54 at EL2: iio-sensor-proxy still started (upstream's 80-iio-sensor-proxy.rules tags fastrpc-adsp* as ssc-light ssc-compass), ran its ssccli wait, stopped by hand; ADSP stayed attached, no crash. Guard moved into the iio-sensor-proxy drop-in (ConditionPathExists=!/dev/kvm). Verified after the update (16:56: proxy skipped at EL2). **Next (postponed by the owner):** the first sensor test on Limine's EL1 entry: `systemctl start book4-sensors`, watch the ADSP, `ssccli --sensor light`, then iio-sensor-proxy / `monitor-sensor --light` (docs/sensors.md, Testing). docs/sensors.md. Was: next the 14"'s sensor registry from the Windows driver files (Rafael's are for the 16": 8380_ss_nx16_veml3328_0.json), then the setup service (/vendor/etc/sensors/sns_reg_config, writable registry seeded from Windows), adsprpcd sensorspd adsp, udev rule for iio-sensor-proxy, at EL1 first. **7.3 at EL1 works (16:16, Limine entry "Omarchy (7.3.4-book4) - EL1", linux protocol with kernel, initramfs and EL1 DTB as separate files, so that entry type is proven too):** all CPUs at EL1, ADSP/CDSP running (kernel-started), all four WSA amps attached, Speakers sink, GPU firmware loaded, charging 2.96 A, book4-el2-sleep skipped by its condition, no failed units, only the usual APM timeout and MultiMedia5 messages (report ~/boot-report-7.3.4-book4-20261123-1617.txt). 2-min s2idle nap at EL1 (16:18, charger in): resumed fine, but cxsd/ddr residency 0 (book4-sleep.csv tag el1): no collapse, as expected at EL1 without `deep` + cntv_arm (the 13 Nov EL1 collapse used both). **Wi-Fi dropped twice after it: my fault, not the kernel:** `tools/omarchy-kernel-report.sh` called `iwctl`, which D-Bus-activated the disabled iwd next to NetworkManager; iwd segfaulted on resume (16:21:24) and on exit deauthenticated wlan0, and `systemctl stop iwd` deauthenticated it once more. iwctl removed from the script, iwd stopped, NetworkManager reconnected. iwd then masked and removed by the owner (stock Omarchy 4.5 also uses NetworkManager and disables iwd). **Omarchy-kernel test for birkskyum (arewearmyet#10) prepared:** `install/arch/omarchy-kernel-test.sh` (edge linux-omarchy 7.3-77 + dtbs 7.3-61 + systemd-stub-omarchy via pacman -U; two UKIs from Omarchy's own 14" DTB, EL2 with our overlay and EL1 stock; Limine entries through the new `/etc/book4/limine-extra.conf`, which book4-boot r612 appends to limine.conf; `remove` undoes it). `hw-test` is birkskyum's tool, installed with `omarchy-mise-install github:birkskyum/arewearmyet hw-test`; it shows its report and asks before sending (results, model, BIOS, hardware IDs, kernel and package versions, names of non-Omarchy kernel options and modules), `--no-send` sends nothing. **Set up 23 November ~12:40:** linux-omarchy 7.3-77 (7.3.0-77-omarchy), dtbs 7.3-61, systemd-stub-omarchy installed; mkinitcpio preset built /boot/initramfs-linux-omarchy.img; UKIs omarchy-kernel-test-el{2,1}.efi; limine.conf 7 entries (the two test entries before Arch GRUB); /boot 630 MB of 1.5 GB. DKMS v4l2loopback not built for it (no linux-omarchy-headers; only the parked camera relay uses it). **First boot (EL2 test entry, ~12:42) hung early:** the top of the screen filled with garbage (the firmware framebuffer overwritten), nothing reached the journal (no boot with 7.3.0-77-omarchy in `journalctl --list-boots`), so it stopped before root was mounted. Verbose variants of both test entries added to the script (earlycon keep_bootcon ignore_loglevel through Limine's cmdline). **Readable after the resolution fix; both EL2 and EL1 test boots stop in the initramfs:** `Timed out waiting for device /dev/disk/by-uuid/4d74e1d5…`, emergency mode, no keyboard. Cause: linux-omarchy builds pinctrl-x1e80100 and qnoc-x1e80100 (UFS suppliers) and i2c-qcom-geni as modules; our mkinitcpio config only names the three UFS modules (enough for linux-book4, where those are built in). Stock Omarchy adds them in /etc/mkinitcpio.conf.d/qualcomm-platform.conf (install/hardware/qualcomm/initramfs.sh), never written here. omarchy-kernel-test.sh now gives linux-omarchy its own /etc/book4/mkinitcpio-omarchy.conf (ours + that list) through its preset; linux-book4's initramfs unchanged. **Next EL1 try (13:15) stopped at 0.716 s** on screen (after gpio-keys), no journal: the only change was the platform modules in the initramfs; stock Omarchy boots Snapdragon with `clk_ignore_unused pd_ignore_unused` (+ `iommu.passthrough=0`), ours not, so the EL1 stock UKI now takes Omarchy's kernel-params.sh parameters on top of ours. **With those parameters it still stopped at ~0.76 s** (screen; the console lags the kernel, so the real stop point is unknown; no journal). The nightly ISO (17 Nov) booted Omarchy's kernel with no UEFI Shell/qebspil/slbounce in front and an older kernel without our EC/USB-C drivers and 14" DT nodes. Isolating test: firmware entry Boot0005 "Omarchy kernel test (EL1, direct)" = the EL1 UKI on sda7 started by the firmware itself (no Shell, no EL2 chain, no Limine), not in BootOrder, BootNext set once. **Direct boot (Boot0005, 13:3x) crashed too:** `[0.964339] Unable to handle kernel paging request at virtual address ffffcac4dd807150`, ESR 0x86000007 (IABT, current EL, level-3 translation fault), right after `amba 1004f000.tmc: Adding to iommu group 13`; screen froze before the call trace, no journal. So not our EL2 chain. Reserved-memory of Omarchy's 14" DTB identical to ours (38 regions). Reported to birkskyum: arewearmyet#10 issuecomment-7101574455 (23 November). **Lead found afterwards:** the nightly ISO (7.3.0-66, booted) had `initramfs_async=0` on its command line, and every stock install has it (omarchy-settings' /etc/limine-entry-tool.d/omarchy-defaults.conf, NoExtract here; Omarchy: since 7.1 the async initramfs unpack races early boot). In the ISO log qcom_scm/qseecom/efivars/arm-smmu probe after `Run /init`; in the crashing boots they ran at 0.85-0.96 s during the background unpack, and the crash came only once our initramfs grew (the ISO's was 156 MB, unpacked synchronously). Test entries now carry `initramfs_async=0 systemd.tty.term.console=dumb`. **Still crashed with them (7.3-78, which the rerun had fetched):** now inside the initramfs while udev loaded modules, at 1.13 s, `Unable to handle kernel execute from non-executable memory at ffffc4bf1c2c5150` (ESR 0x8600000f), again right after the apps SMMU (15000000) assigned its groups; both faulting addresses end in 0x150 at the same page offset (KASLR aside), so a fixed target. Ruled out: async unpack, our EL2 chain, reserved-memory, the Samsung EC modules (not in the initramfs). linux-omarchy 66->78: RPi4 and hibernation config (#2681, #3179; birkskyum's other X1E boot them), our #2968 (EC/USB-C drivers, 14" DT). DTB diff Omarchy 7.3-61 vs ours: Omarchy enables i2c3 and i2c7 with two parade,ps8830 retimers (ours: neither), ours enables spss_glink. Next: Omarchy's kernel with our DTB (`OMARCHY_TEST_DTB=ours`). **Our DTB crashed too (14:28):** same oops (`…04150`, page offset 0x150 again), so not the DTB alone; that boot also printed `scmi_module: Loaded SCMI Vendor Protocol 0x80` just before (our DTB has protocol@80, Omarchy's 7.3-61 has none, and it crashed as well, so not that). The ISO's own 14" DTB (from the .dtbauto of omarchy-live.efi) vs both crashing ones: both enable usb_2 (a200000.usb, + usb_2_hsphy), camss, cci0, i2c9, i2c15 (EC, s2mm006, ov02c10, gpio-leds); the ISO enables usb_mp instead. a200000.usb never appears in the ISO boot log, and dwc3-qcom/phy-snps-eusb2 are in the initramfs, so it probes at the crash point. Next: our DTB minus usb_2 (`OMARCHY_TEST_DISABLE`). **Without usb_2 it still crashed (…43b150)**, again right after the last SMMU group assignment (the second TMC), so not a client device; the target is a fixed object at page offset 0x150 (a function pointer into data). Next: the call trace, with `earlycon=efifb keep_bootcon` (OMARCHY_TEST_DEBUG=1) so the oops prints whole. **ROOT CAUSE (14:5x, full trace via earlycon=efifb):** `pc : 0xffffc2f2779b4150`, `lr : tsens_probe+0x170/0x670 [qcom_tsens]`, `Workqueue: events_unbound deferred_probe_work_func`. tsens_probe+0x16c is `blr` to `priv->ops->init`; for ops_generic_v2 that is `init_common()`, declared `int __init` (drivers/thermal/qcom/tsens.c:932; also init_tsens_v2_no_rpm, init_tsens_v1_no_rpm and the v0_1/v1 init_* are __init), so it lives in the module's .init.text (section 19 in both Omarchy's and our qcom_tsens.ko), freed after module load. Loaded from the initramfs (Omarchy's Qualcomm list has qcom_tsens) the probe is deferred and the retry jumps into freed memory (first unmapped: translation fault; later reused: permission fault). linux-book4 has the same latent bug but loads qcom_tsens from the root fs, where it probes at once. Fixed once upstream in 2019 ("thermal: qcom: tsens: fix crash due to incorrect __init"); `init_common` is `__init` again at least since a7ff82976122 (2020, "Merge tsens-common.c into tsens.c", which carried the annotation over), and ff0cf0ab9073 (2025, V2 enable/calibration) added `__init init_tsens_v2_no_rpm`. Long-standing and latent: it only fires when the probe is deferred past module load. Workaround in the test: qcom_tsens left out of the test initramfs. **It boots (15:06, direct UKI, EL1, Omarchy's DTB):** qcom_tsens loaded from the root fs and reads all zones, which confirms the cause. Report ~/boot-report-7.3.0-78-omarchy-20261123-1508.txt: no failed units, ADSP/CDSP running (EL1), sound card and Speakers sink, Wi-Fi and Bluetooth up, keyboard/touchpad/touchscreen (hid-over-i2c), eDP 2880x1800, samsung_galaxybook_ec battery 28 % and samsung_emuec ports, ov02c10 camera found, no /dev/kvm (EL1). Open: two WSA amps `UNATTACHED` (sdw:1:…:1, sdw:4:…:1; all four Attached on linux-book4). **hw-test on 7.3-78 (sent, 15 working, 4 partly, 3 broken):** broken: hardware video decoding (no iris/venus decoder), headphone jack (sound stays on speakers), WebGPU (only swiftshader); partly: speakers (only the left heard; two WSA amps UNATTACHED), touchscreen (touches register, desktop does not react), USB (no SuperSpeed controller), WebGL (CPU); works: keyboard, touchpad, brightness, microphones, webcam, external screen, built-in screen, GPU, Wi-Fi, Bluetooth, ADSP, CDSP, battery, fans/temperatures (46->80 C under load). The guided lid step froze: DPU `frame done timeout` from ~704 s, then s2idle suspend at 875 s never resumed (journal ends at `PM: suspend entry`); lid and sleep not tested. First guided run was never sent (pending.json replaced by the next run); rerun sent. Sleep hang posted as NOTE-SS3MSVFM96 (with that boot's log). Follow-up with the tsens root cause, the fix and these results: arewearmyet#10 issuecomment-7104749649. Open on our side: the same __init fix for linux-book4 (latent there). **Charging on 7.3-78:** the charger negotiates 20 V/3.25 A (`PD contract … PDO 5`) but the battery charges at ~0.27 A (14.5 V, ~4 W) while awake; on linux-book4 the same charger gives 3.18 A at 15.9 V (~50 W) (our 29 October fix hands the PD contract to the EC). Added as a note to arewearmyet#10 issuecomment-7104749649. The skipped samsung-galaxy-book4-edge-14-support (keyboard rule, Bluetooth address service, tplg symlink to the CRD topology) has equivalents here (99-book4-keyboard.rules, book4-bt-addr.service, book4-edge-firmware's same symlink), so it did not change the results. The stale unowned `updates/qcom/x1e80100/X1E80100-GalaxyBook4Edge-tplg.bin.xz` deleted (23 Nov); the packaged symlink remains. Fix: drop __init from those functions. **Emergency mode once on the default boot (14:25, linux-book4 via Limine):** in the initrd the root device unit went active at 1.244 s (`Found device … fedora`) and inactive 13 ms later (`systemd-fsck-root.service: Bound to unit dev-disk-by…4d74e1d5….device, but unit isn't active`), so /sysroot failed and the emergency shell waited for Enter; after Enter the boot continued. The root btrfs spans sda5+sda6 (same filesystem UUID on both); 64-btrfs.rules sets SYSTEMD_READY=0 until both halves are scanned, and the two udev events raced. First time in 25 boots. Proposed fix (not done, owner to decide): book4-boot's command line `root=PARTUUID=<sda5>` plus `rootflags=device=<sda5>,device=<sda6>,subvol=…`, tried first as test entries. Boot0005 stays outside BootOrder. **Striped boot text under Limine (our kernel too):** the UEFI Shell sets the GOP to 1024x768 and x1-el2-book4.dtso's boot framebuffer says 1024x768 (the 23 October GRUB fix); Limine switched the mode for its menu and left it, so the console no longer matched. book4-boot now writes `interface_resolution: 1024x768` into limine.conf; that alone did not help (still striped): Limine also picks a mode for each booted program unless the entry has `resolution:`, so every generated entry and the Omarchy test entries now carry `resolution: 1024x768` (book4-edge-boot r619). **Fedora deletion approved** (owner), with the pre-4.5 Arch copy: `install/arch/fedora-delete.sh` written (dry run by default; `--yes`: sda4 image + efibootmgr + ESP listing to ~/backup/boot-DATE, removes the five GRUB test entries on subvol=arch, Fedora's files on sda4 and the 7.2.7-book4 initramfs images, deletes subvolumes `root`, `home`, `arch`; never writes the ESP). Not run yet. Found on the way: Fedora's GRUB fallback finds /boot by `/vmlinuz-7.2.7-book4` (kept); `tools/backup/snapshot-arch.sh` only accepted a subvolume named `arch`, so `book4-update` has taken no snapshots since the move to arch-45: now uses the running subvolume (`arch-45-pre-update-*`), book4-update prunes `arch*-pre-update-*`. First step of docs/plan-limine.md. **Run by the owner 23 November (11:23):** subvolumes `root`, `home`, `arch` deleted (only `arch-45` left; space returns as the btrfs cleaner runs), five test entries removed (`omarchy45` kept), /boot down to 222 MB of 2 GB; backup in ~/backup/boot-20261123/ (sda4.img, efibootmgr.txt, esp-listing.txt, Fedora's ESP grub.cfg). Reboot after it fine (owner, 23 November). Next: `install/arch/boot-split.sh` (written, dry run by default): sda4 -> 512 MiB ext4 (same start and UUID) + sda7 1.5 GiB FAT32 XBOOTLDR `BOOK4BOOT`, sectors from `sfdisk -d` of 23 November. **Changed the same day (owner): sda7 is a second ESP** (EFI System, FAT32 `BOOK4ESP`, fstab `/boot`, as stock Omarchy mounts its ESP; old /boot folder content to ~/backup); dry run passed (323 MiB used counted with journal and inode tables). `book4-el2` no longer falls back to a `/boot` labelled BOOK4ESP (in the repo; reaches the system with the next book4-edge-el2 build; /efi is found first anyway). **Split done 23 November 11:38** (second run; the first stopped after `e2fsck -p` exited 1, now accepted): sda4 512 MiB ext4, UUID 3c3204e5 kept, 222 MB used, 180 MB free (one more kernel set of ~100 MB fits during an upgrade); sda7 1.5 GiB EFI System FAT32 `BOOK4ESP` (UUID 7A97-F511, PARTUUID 4f826327-7600-4cab-9da9-a6e57eae65e7) mounted at /boot by fstab (`nofail`); `LIMINE_PART` in /etc/book4/boot.conf; book4-boot menu regenerated (7 entries); backups in ~/backup (GPT dump, fstab, old /boot folder). Reboot after the split fine (owner; /boot is sda7). Step 3 prepared, not run: `install/arch/limine-test.sh` (Limine + a UKI with only our EL2 DTB on sda7, Shell folder `\EFI\book4-el2-limine\` on sda1, firmware entry "Omarchy (EL2, Limine)" created outside BootOrder, one-time test via BootNext); run `book4-update` first (package database from 19 Nov; also the first snapshot with the arch-45 fix). Details in plan-limine.md step 3. **Set up 23 November** (`setup --yes`): limine 12.11.1, systemd-ukify 262.2, python-pefile installed; /boot (sda7) 193 MB used: Limine, limine.conf, kernel set, UKI `EFI/Linux/book4-7.3.4-book4-el2.efi` (sections .linux, .initrd, one .dtb = our EL2 DTB with the zap shader disabled, .cmdline = the GRUB default's, .hwids unused without .dtbauto); `\EFI\book4-el2-limine\` on sda1; firmware entry Boot0001 "Omarchy (EL2, Limine)", BootOrder unchanged (0004,0003,0000,0002). **First Limine boot OK (23 November 11:59, BootNext):** BootCurrent 0001, LoaderInfo Limine 12.11.1, entry "EL2, UKI" (`\EFI\Linux\book4-7.3.4-book4-el2.efi`, systemd-stub 262.2), all CPUs at EL2, /dev/kvm, ADSP and CDSP attached, sound card and Speakers sink, no failed units, only the usual boot messages (APM CMD timeout, MultiMedia5); **no `cutmem`** and no instant reboot. Limine sets LoaderDevicePartUUID to sda7 (fstab mounts it at /boot anyway; /efi still sda1). **Suspend on the Limine boot OK** (12:01-12:03, 2 min on battery, el2-sleep helper active): `cxsd`/`ddr` 97.3 %, `aosd` 0 by design, one CX entry, clean resume (book4-sleep log; the 11.7 W figure is the EC's ~1 % charge step over 2 min, not a drain). **Limine made the default by the owner (23 November, ~12:10):** BootOrder 0001 (Limine), 0004 (Arch GRUB), 0003 (Fedora GRUB fallback), 0000, 0002; plan step 5 done ahead of step 4. **Until step 4 exists, a linux-book4 update does not reach Limine:** the UKI on /boot (sda7) keeps the old kernel and initramfs (modules of a new release would be missing); after a kernel update, rerun `limine-test.sh setup --yes` or pick "Arch GRUB" in Limine's menu. **Step 4 installed** (book4-edge-boot r602.6463e07, 12:13; docs/plan-limine.md step 4): `book4-boot menu` wrote the UKIs of 7.3.4-book4 and 7.2.7-book4s, the 7.3.4 files and a 5-entry /boot/limine.conf (sda7 287 MB of 1.5 GB); kernel updates now reach Limine. book4-edge-el2 2026.11.19-5 installed (`book4-el2 status` all current, Limine chain Boot0001); **first default boot with the generated Limine menu OK (23 November ~12:25):** BootCurrent 0001 (first in BootOrder, no BootNext), entry "Omarchy (7.3.4-book4)" = the UKI book4-boot built, systemd-stub 262.2, all CPUs at EL2, /dev/kvm, ADSP and CDSP attached, Speakers sink, no failed units. **No sound on that boot:** at 53 s, ~4 s after the YouTube Music player started (first playback), SoundWire bus clashes and parity errors on bus 1 (6ab0000/6ad0000; `sdw:1:0:0217:0202:00:1` and `:2`, the left WSA883x pair) left both left amps in `Alert` instead of `Attached`, the speaker pipeline stuck in `[init]` (the 20 October symptom, power.md); restarting PipeWire did not recover them; the kernel (7.3.4-3, 19 Nov) already has the synchronize_irq fix f354813695b4. Earlier boots: the GRUB boot of 11:25 had 2 clashes, the first Limine boot none: sporadic at playback start, not tied to Limine as far as seen. TODO entry added. After a reboot (Limine default again): all four amps `Attached`, no clash, sound back. Earlier: -5 built and in the local [book4] repository (only `status` no longer lists startup-limine.nsh under the GRUB chain): `book4-el2` skips a /boot labelled BOOK4ESP, and owns the Limine chain's folder `\EFI\book4-el2-limine\` (`userspace/el2/startup-limine.nsh`, `book4-el2 install-limine` creates folder and entry outside BootOrder, `update`/the hook keep it current once present, `status` reports it); Shell, qebspil, slbounce, startup.nsh byte-identical to -1; the hook will rewrite the Limine startup.nsh once (header comment only). **`cutmem`:** this boot's memory map (no cutmem) ends at 0xbffffffff (Normal zone 0x100000000-0xbffffffff); the cut range 0x8800000000-0x8fffffffff is not in it at all, so there is nothing to cut on the current firmware and kernel. Still to test (plan step 3): a day of use without `cutmem`, entries 2 (kernel + `dtb_path` at EL2) and 3 (EL1), the way back to GRUB.

**Updated 22 November 2026**: Replied on jglathe/linux_ms_dev_kit#102 (issuecomment-7079688959; jglathe credited our syscon fix, now in 7.3.3-jg-2): their T14s ADSP stuck awake in s2idle may be `qcom_adsp_pwr_lmts` crashing it (dead DSP at EL2 looks frozen in qcom_stats); our blacklist, the 7.3 LPASS va/wsa macro fix and our ~0.7 W EL2 numbers. Open: birkskyum (arewearmyet#10) asks for a run of Omarchy's kernel (linux-omarchy 7.3-75, edge) beside ours; side-by-side test entry "omarchy-el2" prepared, not installed yet (edge alsa-ucm-conf would collide with book4-edge's Samsung UCM files; hw-test not available on the stable channel). **Limine plan written** (docs/plan-limine.md, not started): sda4 /boot measured (2 GB ext4, 1.3 GB used, ~1 GB of it Fedora rescue/fc45 files and old copies); clean it with the Fedora deletion, split into 512 MiB ext4 (same UUID, GRUB unaffected) + ~1.5 GiB FAT32 for Limine, Limine started by the UEFI Shell after qebspil/slbounce from a second firmware entry, our EL2 DTB per entry, `cutmem` need to be tested.

**Updated 20 November 2026**: **[book4] online** (docs/packages-online.md): workflow `.github/workflows/packages.yml` (manual) builds linux-book4, book4-edge, book4-edge-boot and book4-edge-el2 on GitHub's arm64 runner in an Arch Linux ARM container (official rootfs, signature checked against keys/archlinuxarm-build-system.asc), signs with makepkg --sign and publishes a signed repository in the release `repo`. Signing key E75AAB6A080DCE59DC84259D595D834A7E98BBCE (ed25519, made in RAM, private part only in the secret BOOK4_SIGN_KEY, public in keys/book4-repo.asc). linux-book4's PKGBUILD pins `_commit` (book4/7.3 f1ea704) and falls back to packages/linux-book4/config (this machine's .config). Firmware never built there. Nothing changed on the laptop: it keeps the local [book4]. First publish 09:50 (run 44713389902, after three fixes: DisableSandbox, explicit mirror list, runner paths allowed in the home-path check since the upstream UEFI Shell carries one): book4-edge r581, book4-edge-boot r581, book4-edge-el2 -2; signatures checked from outside with keys/book4-repo.asc; the CI-built Shell, qebspil and slbounce are byte-identical to the installed ones. Kernel published 13:30 (run 44734722137, ~70 min build; signature checked from outside; same 5910 files as the installed linux-book4 7.3.4-3). The first two kernel runs built and signed fine but were stopped by the home-path check (upstream kernel files name developers' homes: BPF iterators skeleton, scripts in the headers); the check now reads only the build metadata (.BUILDINFO/.PKGINFO), where a local build shows `/home/<user>`. Local builds record that path, so publish only CI builds. All four public packages are now in the release `repo`.

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

## How the machine runs today (26 November 2026)

- **Hardware:** Galaxy Book4 Edge 14" NP940XMA (X1E80100), 476.7 GB UFS:
  `sda1` firmware ESP (260 MiB FAT32, `/efi`, shared with Windows), `sda2` MSR,
  `sda3` Windows (300 GB NTFS), `sda4` fallback GRUB `/boot` (512 MiB ext4,
  unmounted normally), `sda5` + `sda6` two-device btrfs (196 GB, subvolume
  `arch-45`), `sda7` second ESP `BOOK4ESP` (1.5 GiB FAT32, `/boot`, Limine +
  UKIs). Fedora (`root`, `home`) and pre-4.5 `arch` were deleted 23 November
  ([fedora-retired.md](fedora-retired.md)); `~/fedora-archive/` keeps Fedora's
  archived home and 7.2 `.git` trees.
- **Daily system:** Arch Linux ARM + **Omarchy 4.5** (from `[omarchy]` repo),
  kernel **`linux-book4` 7.3.4** (branch `book4/7.3` of
  `n1c0la84/linux-book4-edge`, built natively on Arch via `packages/linux-book4`;
  `7.2.7-book4s` remains as fallback), booted **at EL2** via **Limine**
  (`Boot0001` "Omarchy (EL2, Limine)" -> UEFI Shell in `\EFI\book4-el2-limine\`
  -> `qebspil` + `slbounce` -> Limine on `sda7` -> EL2 UKI; no `cutmem` needed
  on Limine/7.3). Arch GRUB (`Boot0004`, `\EFI\book4-el2-arch\`) and Fedora GRUB
  (`Boot0003`, `\EFI\fedora\`) stay as fallbacks.
- **Book4 layer packages:** built in `packages/` (`linux-book4`, `book4-edge`,
  `book4-edge-boot`, `book4-edge-el2`, `fastrpc`, `libssc-book4`,
  `iio-sensor-proxy-book4`, `book4-sensors`, `libfprint-sdcp`, plus local-only
  `book4-edge-firmware`). This laptop uses its local `[book4]` repo
  (`/var/lib/book4-repo`); the public packages are also built and signed in CI
  ([packages-online.md](packages-online.md)), and `book4-edge-firmware` is
  backed up to the private LAN repo (`install/arch/book4-private.sh`).
- **Updates:** `book4-update` (snapshots `arch-45` via
  `tools/backup/snapshot-arch.sh`) or `omarchy-update`. `91-book4-boot.hook`,
  `92-book4-limine.hook` and `95-book4-el2.hook` keep `/boot`, `sda4` GRUB and
  `/efi` current on package upgrades ([updates.md](updates.md)).
- **Android development:** Google Android CLI `1.1.16717390` for Linux ARM64
  at `~/.local/bin/android`; SDK root `~/Android/Sdk`.

## What works (EL2, 7.3.4-book4)

Deep sleep in `s2idle` with both DSPs (~0.70 W at EL2, ~0.77–0.84 W at EL1,
AOSD off everywhere; [power.md](power.md)); four speakers at PA 23 (+12 dB)
with crossover, limiter, PipeWire clock resync fix (`book4-clock.conf` +
`rtkit`) and WebRTC mic noise suppression ([audio.md](audio.md)); ambient light
sensor (VEML3328 via SSC) + `book4-autobrightness` at EL1 and EL2
([sensors.md](sensors.md)); webcam in browsers/PipeWire ([camera.md](camera.md));
fingerprint reader (`libfprint-sdcp` + Windows enrolment import); EFI variables
and RTC; KVM; battery and 20 V charging (including awake charging, hot replug,
and unplug during sleep); Wi-Fi (`c5-00302`, [firmware.md](firmware.md)) and
Bluetooth; awake drain logger (`book4-drain`) and resume health check
(`book4-resume-check`).

Low battery: Omarchy warns at 10 %, `book4-battery-warn` at 8 % and 5 %,
UPower powers off at 3 %. Under heavy load the EC's reading can drop from ~8 %
to 0 in seconds, so plug in at the 8 % warning.

Not working / open: external monitor over USB-C DP (AUX timeouts; HDMI works);
NPU inference (`dspqueue` hang; `dspsignal` ported, untested); Iris hardware
decode faults on odd-size streams (e.g. 2832×1700; 1080p works from fresh boot,
mpv uses `hwdec=auto-safe`); Qt V4L2 camera apps (`camera-relay.sh` parked);
sporadic SoundWire clash after resume (`TODO.md`); charging through VIA VL817
powered USB-C hub; ~0.6 W board power delta over Windows in sleep (`0.11 W` vs
`0.70 W`) and ~7.1 W average awake drain.

## In progress

- **Board sleep power (~0.70 W vs Windows 0.11 W):** `tools/power/ec-standby-test.sh`
  (MODS + HPDC together) ready for an overnight run; next candidates in
  [ROADMAP.md](ROADMAP.md) section 2.
- **Awake battery drain (~7.1 W avg):** `book4-drain` collecting per-minute
  data; report with `book4-drain report`.
- **SoundWire clash & USB-C/xHCI resume bugs:** upstream report drafts in
  `docs/upstream-drafts/` (need retest on an untainted kernel before sending);
  `book4-resume-check` mitigates fingerprint xHCI / `fprintd` / `adsprpcd` after
  resume.
- **Toward stock `linux-omarchy`:** `qcom_tsens` initramfs crash verified fixed
  on 7.3-79 (Tested-by sent 25 Nov); remaining upstream items in
  [ROADMAP.md](ROADMAP.md) and [upstream.md](upstream.md).
- **Live ISO / reset installer:** `install/arch/live-iso.sh`, `book4-install.sh`
  and `rescue-usb.sh` still target the pre-23-Nov `arch`/GRUB layout and need
  updating for `arch-45`/Limine before reuse.

## Hard rules

- **Boot:** keep `cma=256M` (and `cutmem` on GRUB entries; Limine on 7.3 does
  not need `cutmem`). Never delete anything from the firmware ESP (`sda1`).
  Keep `linux-modules-cleanup.service` masked while Arch has more than one
  kernel. Never run `omarchy-reinstall-configs`, `omarchy-refresh-limine`,
  `omarchy-setup-security-fingerprint` or Omarchy's `post-install/pacman.sh`.
- **Resets the machine:** reading `clk_summary` after LPASS powers down,
  unbinding `lpasscc-sc8280xp`, reading `0xAF20000` at EL1, stopping DSPs at
  EL2 (votes stay stuck), a hung NPU session (reboot at once; no NPU runs
  that can hang until dspsignal works). Unbinding `qcom-soundwire` controllers
  breaks audio until reboot (IRQ type mismatch on re-probe).
- **Speakers:** never hand the gain to the amps' DRE (garbled output, one
  PMIC reset). Thermal at PA 23 is a non-issue (coils +3 °C).
- **Keep blacklisted:** `qcom_adsp_pwr_lmts` (crashes the ADSP on this
  machine; Samsung disables it on Windows too) and `qcom_spss_nvm` (probe loop
  on 7.3).
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
