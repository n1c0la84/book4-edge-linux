# Credits and provenance

This repository combines our own work with work by others. Everything taken
from elsewhere is listed here with its origin, author and licence. Original
copyright and licence headers are kept intact in every copied file.

## Taken from others

| What | Where in this repo | Origin | Author / owner | Licence | Modified? |
|---|---|---|---|---|---|
| `ene-kb9058-battery.c`, `samsung-emuec.c` | `drivers/anatase/` | [anatase-org/patchwork](https://github.com/anatase-org/patchwork), branch `anatase-7.2` | Antheas Kapenekakis | GPL-2.0-only | no; our 7.2 changes are separate patches in `drivers/anatase/patches/` |
| Anatase device tree (compiled, 7.2 era) | `dts/*.anatase.dtb` | built from Anatase `anatase-7.2` DTS sources and 7.2 `hamoa.dtsi` | Anatase project; upstream Qualcomm/Linaro DTS authors | as the Linux DTS sources (SPDX headers; Qualcomm DTS are typically BSD-3-Clause) | compiled and padded only (`dtc -p 8192`) |
| Earlier device tree (compiled, 7.2 era) | `dts/*.book4-own.dtb` | Galaxy Book4 Edge DTS series v6 posted to linux-arm-msm, rebased onto 7.2.6 `hamoa.dtsi` | Maxim Storetvedt (series); upstream Qualcomm/Linaro DTS authors | as the Linux DTS sources | rebased, hardware fixes of our own |
| UCM profile | `userspace/audio/ucm2/` | [alsa-ucm-conf](https://github.com/alsa-project/alsa-ucm-conf) `ucm2/Qualcomm/x1e80100/HiFi.conf` and `X1E80100-CRD.conf` | Krzysztof Kozlowski (Linaro) and alsa-ucm-conf contributors | BSD-3-Clause | yes, adapted for four WSA883x speakers (woofers + tweeters) and DMIC gain (described in file headers) |
| Audio topology | not shipped; aliased by `book4-edge-firmware` | linux-firmware `qcom/x1e80100/X1E80100-CRD-tplg.bin` | Qualcomm / Linaro | linux-firmware terms | no (symlink only) |
| Wi-Fi firmware c5-00302 | not shipped; documented in `docs/firmware.md` | Debian `firmware-atheros` 20251111-1 | Qualcomm | linux-firmware terms | no |
| Wi-Fi `board.bin` | not shipped; documented | upstream `board-2.bin`, entry for subsystem 1107 / board-id 82 | Qualcomm | linux-firmware terms | extracted only |
| DSP / GPU firmware, `tcblaunch.exe`, sensor config/registry | not shipped; staged locally by `install/arch/firmware-stage.sh` | Samsung / Qualcomm / Microsoft Windows drivers on this laptop | Samsung / Qualcomm / Microsoft | proprietary | n/a |
| Fingerprint import, mic noise suppression, sensor setup & SSC patches | `userspace/fingerprint/book4-fingerprint-import`, `userspace/audio/pipewire/book4-mic-ns.conf`, `userspace/sensors/book4-sensors-setup`, `packages/libssc-book4/0001-*.patch`, `packages/iio-sensor-proxy-book4/0001-*.patch` | [rafaelmnz/SB4-Edge-Linux](https://github.com/rafaelmnz/SB4-Edge-Linux) (`overlay/fingerprint`, `overlay/audio`, `overlay/sensors`, `patches/`) | Rafael Meneses | GPL-2.0 | adapted to the 14" model (`nx14`) and Arch packaging |
| `fastrpc`, `libssc`, `iio-sensor-proxy` package recipes | `packages/fastrpc/`, `packages/libssc-book4/`, `packages/iio-sensor-proxy-book4/` | [quic/fastrpc](https://github.com/quic/fastrpc) (pinned to Rafael Meneses' commit `89508eae`), [Dylan Van Assche / libssc](https://codeberg.org/DylanVanAssche/libssc), [hadess / iio-sensor-proxy](https://gitlab.freedesktop.org/hadess/iio-sensor-proxy), Arch Linux recipes | Qualcomm Innovation Center; Dylan Van Assche; Bastien Nocera & contributors | BSD-3-Clause (`fastrpc`), GPL-3.0-or-later (`libssc`), GPL-3.0-only (`iio-sensor-proxy`) | `fastrpc` omits auto-start rules; `libssc-book4` & `iio-sensor-proxy-book4` apply Rafael's patches |
| `libfprint-sdcp` recipe | `packages/libfprint-sdcp/PKGBUILD`, `userspace/fingerprint/libfprint-sdcp.spec` | [libfprint MR !547](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/547) (SDCP v2, egismoc), Arch/Fedora `libfprint` recipes, approach from [lanlanndn/galaxybook4-fingerprint](https://github.com/lanlanndn/galaxybook4-fingerprint) | libfprint contributors & MR !547 authors | LGPL-2.1-or-later | builds MR !547 commit directly |
| Sleep kernel patches `0001`–`0009`, `0011`–`0014`, `0019`–`0026` | `tools/kernel/sleep-backport/` | upstream Linux 7.3 / linux-next and jglathe's 7.2 tree (each patch keeps its `From:` and upstream commit); `0026` as posted to the list, via x1e-sleep | Maulik Shah, Mukesh Ojha, Thomas Gleixner, Ajay Kumar Nandam, Praveen Talari (Qualcomm/Linux); Stephan Gerhold (remoteproc attach); Oleg Keri (`0026`, SoundWire) | GPL-2.0-only | backported to 7.2.7; `0010` and `0015`–`0018` are ours |
| Sleep kernel patches `0027`–`0028` (SHM bridge self-owner) | `tools/kernel/sleep-backport/` | jglathe's tree, via [justririll/x1e-dsp](https://github.com/justririll/x1e-dsp) | Kirill Mitrofanov (x1e-dsp); jglathe's tree | GPL-2.0 | `0027` is only the header hunk of their `0002`; its DTS part is in `dts/src/x1-el2-book4.dtso` |
| Sleep kernel patches `0029`–`0036` (SCMI generic ext & memlat DVFS) | `tools/kernel/sleep-backport/` | upstream Linux / Qualcomm postings | Pragnesh Papaniya, Sibi Sankar (Qualcomm) | GPL-2.0-only | backported to 7.2.7 / ported to `book4/7.3` |
| Sleep kernel patch `0040` (Iris non-TZ firmware loading) | `tools/kernel/sleep-backport/` | ported from Stephan Gerhold's venus non-TZ start; firmware stream SID `0x1942` from jglathe via [justririll/x1e-dsp](https://github.com/justririll/x1e-dsp) | Stephan Gerhold (Linaro); Jens Glathe | GPL-2.0-only | adapted for `qcom-iris` and 7.3 `qcom_pas` API |
| Sleep kernel patch `0041` (`dspsignal`) | `tools/kernel/sleep-backport/`, `tools/npu/fastrpc-patches/` | ported from Qualcomm's downstream `dsp-kernel` (`dsp-kernel.lnx.3.2.r17`) | Qualcomm | GPL-2.0-only | adapted to upstream `fastrpc` driver |
| Sleep kernel patch `0043` (Oryon X1 DC ZVA erratum) | `tools/kernel/sleep-backport/` | adapted from [justririll/x1e-sleep](https://github.com/justririll/x1e-sleep) (`x1-dc-zva-erratum-and-cl5.patch`), design by Marc Zyngier | Marc Zyngier; Kirill Mitrofanov (x1e-sleep) | GPL-2.0-only | adapted to `book4/7.2-sleep` and `book4/7.3`; `0044` (KVM `HCR_EL2.TDZ`) is ours |
| `el1tmr.c`, `aoss_cxsd_only.c` | `tools/power/sleep-modules/` | [justririll/x1e-sleep](https://github.com/justririll/x1e-sleep) commit `4e84b60` | Kirill Mitrofanov (justririll) | GPL-2.0 / GPL-2.0-only (file headers) | no |
| `qcom_adsp_pwr_lmts.c`, `book4_dsp_sleepstate.c` | `tools/power/sleep-modules/` | based on x1e-sleep's `adsp-pwr-lmts` and `adsp-sleepstate` | justririll; changes ours | GPL-2.0 / GPL-2.0-only | yes (PM notifier timing; both DSPs; neither is used: see `docs/power.md`) |
| `qebspil-aoss-load-state.patch` | `install/el2/` | x1e-sleep commit `4e84b60`, for [stephan-gh/qebspil](https://github.com/stephan-gh/qebspil) `8e4d9e6` | justririll | GPL-2.0-only (as qebspil) | no |
| `qebspil`, `slbounce`, UEFI Shell | built from pinned commits/releases by `packages/book4-edge-el2/PKGBUILD` (and `install/el2/build-efi.sh`) | [stephan-gh/qebspil](https://github.com/stephan-gh/qebspil), [TravMurav/slbounce](https://github.com/TravMurav/slbounce), [pbatard/UEFI-Shell](https://github.com/pbatard/UEFI-Shell) (`26H1`) | Stephan Gerhold; Nikita Travkin; Pete Batard / TianoCore EDK II | GPL-2.0-only / BSD-3-Clause / BSD-2-Clause | our slbounce change is `install/el2/slbounce-tcblaunch-fallback.patch` |
| EL2 device tree overlay | `dts/src/x1-el2-book4.dtso` | upstream `arch/arm64/boot/dts/qcom/x1-el2.dtso` | Qualcomm/Linaro DTS authors | as the Linux DTS sources | yes (no ADSP/CDSP iommus; DSPs `qcom,broken-reset`, Iris firmware stream, sleepstate entries) |
| `hw-monitor-snapdragon.patch` | `userspace/desktop/` | patch against [meviusisback/omarchy-hw-monitor](https://github.com/meviusisback/omarchy-hw-monitor) 1.7.0 | meviusisback; Snapdragon changes ours | MIT / GPL-2.0-only | adds Snapdragon tsens and `book4-gpu-busy` probe |

## Ideas and findings from others we relied on

- **Anatase** (Antheas Kapenekakis): ENE KB9058 EC protocol, S2MM006 Type-C drivers and charging switch command, 7.3 kernel base and reworked Samsung EC/emuec drivers, QSEECOM allowlist, keyboard HID quirk.
- **Rafael Meneses (`rafaelmnz/SB4-Edge-Linux`)**: Windows-to-Linux fingerprint import, WebRTC mic noise suppression, and the entire Qualcomm Sensor Core (SSC) ambient light sensor stack (`adsprpcd`, `libssc`, `iio-sensor-proxy`).
- **Birk Skyum (`omacom/omarchy`, `birkskyum/arewearmyet`)**: Omarchy Snapdragon port, `hw-test`, `qcom_aoss` upstreaming collaboration, and X1E sleep/kernel comparisons.
- **Launchpad bug #2084591**: the keyboard tablet-pad misclassification that our udev rule works around.
- **`zensanp/linux-book4-edge`** and **`hegjon`**: community testing, speaker side verification, and 14" hardware reports.
- **Debian firmware packagers**: `firmware-atheros` archive preserving the working `c5-00302` ath12k firmware.
- **Kirill Mitrofanov (`justririll/x1e-sleep`, `x1e-dsp`)**: first full DRIPS on X1E and the EL2 deep sleep recipe.
- **Stephan Gerhold** (`qebspil`, remoteproc attach, non-TZ Iris/venus) and **Nikita Travkin** (`slbounce`): the EL2 boot chain with DSPs running.
- **Qualcomm upstream developers** (Maulik Shah, Ajay Kumar Nandam, Sibi Sankar, Pragnesh Papaniya, Mukesh Ojha, Praveen Talari): PDC, LPASS macro runtime PM, and SCMI/memlat work.
- **Michael Burch** (Dell XPS 13 EL1 s2idle `tick_freeze()` / CNTV finding), **Christian Schmidbauer** (`qcom_tsens` `__init` crash fix), **Marc Zyngier** & **`icecream95/x1e-crash`** (Oryon DC ZVA erratum and reproducer), **`armbrusl/x1e-npu`** (Hexagon CDSP FastRPC setup), and the **`linux_ms_dev_kit` #94/#102** community (Jens Glathe, Stewings, aruhier, Val Packett, dwhinham).

## Our own work

- Reverse engineering of the EC protocol from Windows `EC2.sys` (`docs/ec-protocol.md`, `tools/ec/`), done independently of Anatase and matching it, plus the `0x90`/`0x91` charger input-limit discovery.
- Packaging and CI pipeline for the Arch/Omarchy Book4 layer (`packages/`, `.github/`), `book4-boot` (Arch GRUB + Limine EL2 UKI generator and pacman hooks), `book4-el2` (EL2 ESP manager), `book4-update`, `book4-autobrightness`, `book4-drain`, `book4-resume-check`, and `book4-sleep-log`.
- Kernel fixes and investigations: `drivers/anatase/patches/` (PD retry, sleep quiesce, wake on plug-in, CC orientation), 14" camera/tweeters/fingerprint DT patches, CoreSight CTCU sleep blocker fix on 7.3, `sleep-backport` `0010`, `0015`–`0018`, `0037`–`0039`, `0042`, `0044`, `0045` (arch timer far-deadline EL1 s2idle fix), `cntv_arm.c`, and the `qcom_tsens` initramfs deferred-probe root cause analysis.
- Audio UCM adaptation for four speakers, PipeWire crossover/limiter/clock resync fix, and analysis (`docs/audio.md`).
- Bluetooth public-address service (`userspace/bluetooth/`) and Windows registry helper.
- `drivers/book4-ec/` and `drivers/book4-kbd-backlight/` (earlier standalone drivers, superseded by Anatase's EC driver).
- Finding that Samsung's ADSP image lacks `charger_pd` (why `pmic-glink` cannot work here) and that `qcom_adsp_pwr_lmts` crashes this ADSP.
