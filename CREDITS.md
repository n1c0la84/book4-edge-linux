# Credits and provenance

This repository combines our own work with work by others. Everything taken
from elsewhere is listed here with its origin, author and licence. Original
copyright and licence headers are kept intact in every copied file.

## Taken from others

| What | Where in this repo | Origin | Author / owner | Licence | Modified? |
|---|---|---|---|---|---|
| `ene-kb9058-battery.c` | `drivers/anatase/` | [anatase-org/patchwork](https://github.com/anatase-org/patchwork), branch `anatase-7.2` | Antheas Kapenekakis | GPL-2.0-only | no |
| `samsung-emuec.c` | `drivers/anatase/` | same | Antheas Kapenekakis | GPL-2.0-only | no; our change is a separate patch in `drivers/anatase/patches/` |
| Anatase device tree (compiled) | `dts/*.anatase.dtb` | built from the Anatase `anatase-7.2` DTS sources and their 7.2 `hamoa.dtsi` | Anatase project; upstream Qualcomm/Linaro DTS authors | as the Linux DTS sources (see their SPDX headers; Qualcomm DTS are typically BSD-3-Clause) | compiled and padded only (`dtc -p 8192`) |
| Our earlier device tree (compiled) | `dts/*.book4-own.dtb` | Galaxy Book4 Edge DTS series v6 posted to linux-arm-msm, rebased by us onto 7.2.6 `hamoa.dtsi` | Maxim Storetvedt (series); upstream Qualcomm/Linaro DTS authors | as the Linux DTS sources | rebased, hardware fixes of our own |
| UCM profile | `userspace/audio/ucm2/` | [alsa-ucm-conf](https://github.com/alsa-project/alsa-ucm-conf) `ucm2/Qualcomm/x1e80100/HiFi.conf` and `X1E80100-CRD.conf` | Krzysztof Kozlowski (Linaro) and alsa-ucm-conf contributors | BSD-3-Clause | yes, adapted for two WSA883x speakers (described in the file headers) |
| Audio topology | not shipped; aliased at install time | linux-firmware `qcom/x1e80100/X1E80100-CRD-tplg.bin` | Qualcomm / Linaro | linux-firmware terms | no (symlink only) |
| Wi-Fi firmware c5-00302 | not shipped; documented in `docs/firmware.md` | Debian `firmware-atheros` 20251111-1 | Qualcomm | linux-firmware terms | no |
| Wi-Fi `board.bin` | not shipped; documented | upstream `board-2.bin`, entry for subsystem 1107 / board-id 82 | Qualcomm | linux-firmware terms | extracted only |
| DSP / GPU firmware | not shipped; documented | Samsung/Qualcomm Windows drivers | Samsung / Qualcomm | proprietary | n/a |
| Sleep kernel patches 0001-0009, 0011-0014, 0019-0026 | `tools/kernel/sleep-backport/` | upstream Linux 7.3 / linux-next and jglathe's 7.2 tree (each patch keeps its `From:` and upstream commit); 0026 as posted to the list (not merged), via x1e-sleep | Maulik Shah, Mukesh Ojha, Thomas Gleixner, Ajay Kumar Nandam, Praveen Talari (Qualcomm/Linux); Stephan Gerhold (remoteproc attach); Oleg Keri (0026, SoundWire) | GPL-2.0-only | backported to 7.2.7; 0010 and 0015-0018 are ours |
| Sleep kernel patches 0027-0028 (SHM bridge self-owner) | `tools/kernel/sleep-backport/` | jglathe's tree, via [justririll/x1e-dsp](https://github.com/justririll/x1e-dsp) `clk-provider/patches/0001-0002` | Kirill Mitrofanov (x1e-dsp); jglathe's tree | GPL-2.0 | 0027 is only the header hunk of their 0002; its DTS part is in our `dts/src/x1-el2-book4.dtso` |
| `el1tmr.c`, `aoss_cxsd_only.c` | `tools/power/sleep-modules/` | [justririll/x1e-sleep](https://github.com/justririll/x1e-sleep) commit 4e84b60 | justririll | GPL-2.0 / GPL-2.0-only (file headers) | no |
| `qcom_adsp_pwr_lmts.c`, `book4_dsp_sleepstate.c` | `tools/power/sleep-modules/` | based on x1e-sleep's `adsp-pwr-lmts` and `adsp-sleepstate` | justririll; changes ours | GPL-2.0 / GPL-2.0-only | yes (PM notifier timing; both DSPs; neither is used: see `docs/power.md`) |
| `qebspil-aoss-load-state.patch` | `install/el2/` | x1e-sleep commit 4e84b60, `qebspil/0001-pil-send-AOSS-load_state-off-on-before-starting-ADSP.patch`, for [stephan-gh/qebspil](https://github.com/stephan-gh/qebspil) 8e4d9e6 | justririll | GPL-2.0-only (as qebspil) | no |
| qebspil, slbounce | not shipped; built from pinned commits by `install/el2/build-efi.sh` | [stephan-gh/qebspil](https://github.com/stephan-gh/qebspil), [TravMurav/slbounce](https://github.com/TravMurav/slbounce) | Stephan Gerhold; Nikita Travkin | GPL-2.0-only / BSD-3-Clause (see each) | our slbounce change is `install/el2/slbounce-tcblaunch-fallback.patch` |
| EL2 device tree overlay | `dts/src/x1-el2-book4.dtso` | upstream `arch/arm64/boot/dts/qcom/x1-el2.dtso` | Qualcomm/Linaro DTS authors | as the Linux DTS sources | yes (no ADSP/CDSP iommus; DSPs `qcom,broken-reset`, sleepstate entries) |

## Ideas and findings from others we relied on

- **Anatase** also independently decoded the ENE KB9058 EC protocol, found the
  S2MM006 Type-C controllers and their charging switch command, corrected the
  speaker and redriver descriptions, and wrote the QSEECOM allowlist patch and
  the keyboard HID quirk.
- **Launchpad bug #2084591**: the keyboard tablet-pad misclassification that our
  udev rule works around.
- **zensanp/linux-book4-edge** (issues #3, #4): community testing and reports on
  this hardware.
- The Debian firmware packagers, whose `firmware-atheros` archive preserved the
  working ath12k firmware.
- **justririll/x1e-sleep** (ASUS Vivobook S15): the first full DRIPS on X1E,
  and the recipe our EL2 deep sleep is ported from (`el1tmr`, the LPASS and
  geni fixes, the panel supplies, qebspil's AOSS message).
- **Stephan Gerhold** (qebspil, remoteproc attach) and **Nikita Travkin**
  (slbounce): the EL2 boot chain with the DSPs running.
- **Qualcomm's upstream work** (Maulik Shah's PDC series, Ajay Kumar
  Nandam's LPASS macro runtime PM): most of the sleep kernel's patches.
- The **linux_ms_dev_kit #94** thread (jglathe, Stewings, aruhier, Val Packett
  on linux-arm-msm) for comparisons across X1E/X1P machines.

## Our own work

- Reverse engineering of the EC protocol from the Windows `EC2.sys` driver
  (`docs/ec-protocol.md`, `tools/ec/`), done before we knew of Anatase's work
  and matching it.
- `drivers/book4-ec/`: our EC battery driver.
- The keyboard backlight command and its observed behaviour, and the experimental
  driver in `drivers/book4-kbd-backlight/` (`docs/keyboard-backlight.md`).
- `drivers/anatase/patches/0001-*`: the charger hot-plug PD retry.
- The UCM adaptation, topology alias and its analysis (`docs/audio.md`).
- The Bluetooth public-address service and the Windows registry helper.
- The kernel-install boot hook, the dracut/udev/modprobe snippets, the Wi-Fi
  firmware findings and the installer.
- The finding that Samsung's ADSP image has no `charger_pd`, so `pmic-glink`
  cannot work on this machine.
