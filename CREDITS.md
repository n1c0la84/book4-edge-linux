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

## Our own work

- Reverse engineering of the EC protocol from the Windows `EC2.sys` driver
  (`docs/ec-protocol.md`, `tools/ec/`), done before we knew of Anatase's work
  and matching it.
- `drivers/book4-ec/`: our EC battery driver.
- `drivers/anatase/patches/0001-*`: the charger hot-plug PD retry.
- The UCM adaptation, topology alias and its analysis (`docs/audio.md`).
- The Bluetooth public-address service and the Windows registry helper.
- The kernel-install boot hook, the dracut/udev/modprobe snippets, the Wi-Fi
  firmware findings and the installer.
- The finding that Samsung's ADSP image has no `charger_pd`, so `pmic-glink`
  cannot work on this machine.
