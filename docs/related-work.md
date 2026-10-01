# Related work, and what is actually ours

Surveyed 1 October 2026. This machine has more people working on it than it
looks, and several of them are ahead of us in places. Knowing who has what
avoids reporting things that are already known — and avoids missing things we
could simply take.

## The projects

### Anatase — `anatase-org/patchwork`, branch `anatase-7.2`

The active upstream for this laptop. A Fedora ARK kernel tree carrying:

- `drivers/power/supply/ene-kb9058-battery.c` — the EC battery driver we use
- `drivers/usb/typec/samsung-emuec.c` — Type-C, charging, DP alt-mode
- the QSEECOM allowlist patch (20 September — ten days before we drafted our own)
- a HID multi-input quirk for our keyboard
- the UFS Kioxia timestamp quirk
- the device tree we boot, with `pmic-glink` removed
- CAMSS support for X1P42100
- a `linux-firmware` fork with an ath12k board alias for this machine

Kernel RPMs at `ghcr.io/anatase-org/kernel:f44-aarch64`. See [kernel.md](kernel.md).

**Their EC protocol decode matches ours byte for byte** — same `0x30`/`0x40`/`0x50`
framing, same `0xFF10`/`0xF480` mailbox, same register offsets. Two independent
efforts, one answer. Where we disagreed with a third implementation (design vs
last-full capacity), Anatase's comment cites the same ACPI evidence we did.

### ciscobugger — `ciscobugger/book4-edge-linux`

**Book4 Edge 15.6" (NP750XQA, X1P42100 — X Plus, not X Elite.)** The closest
sibling to this repository, and ahead of us in several places:

- **Camera works.** Sensor is an **OV02C10**, driven by the in-tree driver plus
  a DT node, with a board-specific HFLIP patch because the module is mounted
  rotated 180 degrees.
- **A full EC command descriptor table** pulled out of `EC2.sys`: `.data` at
  `0x14000d5b0`, four bytes per entry, index `cmd - 0x80`, with payload lengths.
  It confirms `0x88` read / `0x89` write and explains why `0x86`/`0x87` are
  inert (zero payload both ways).
- **A separate charging command namespace** from `EmuEc.sys`, not `0x80`-based:
  `CMD_CHG_CUR` `0x14`, `CMD_CHG_STATE` `0x20`, `CMD_INP_CUR` `0x3f`. Charge
  current limiting lives here.
- `scripts/ath12k-bdencoder` and `make-board-2.sh` for board data.
- Touchpad varies by SKU, with a method for reading your own.

**Two things from them that change our picture:**

1. Their firmware set includes **`battmgr.jsn`**. The 15.6" ADSP image *does*
   run the charger protection domain that ours lacks. So "pmic-glink cannot
   work on the Book4 Edge" is **too broad** — it is true of this 14" firmware,
   not of the product line. Corrected in [upstream.md](upstream.md).
2. Their charging commit of 17 September — *"act on every attach code, stage
   the PD request ourselves, ignore bad temperature reads"* — is the same
   insight as our PD retry patch, found two weeks earlier on their own driver.
   Ours remains a valid fix to Anatase's driver; it is not a discovery.

Their EC table stops at commands `>= 0x80`; the dispatcher branches elsewhere
for anything below, and they did not follow it. Our keyboard backlight command
(`{0x10, x, level}` at address `0x62`) is in exactly that unexplored space,
which is why it is still ours — see [keyboard-backlight.md](keyboard-backlight.md).

### Saddytech — `Saddytech/Galaxy-Book4-Edge-linux`

The battery driver recommended in `zensanp/linux-book4-edge#4`, and the one
most people are running. Same EC protocol, two bugs we can show:
design/last-full swapped, and the rate cast to `s16` when the EC reports an
unsigned magnitude. Details in [upstream.md](upstream.md).

### zensanp — `zensanp/linux-book4-edge`

The community issue tracker for this laptop. Issue #3 is Wi-Fi, #4 battery, #8
USB-C and audio. The maintainer owns a 14" like ours.

## Other distributions

- **Omarchy Dragon** — official Snapdragon X support for Omarchy (Arch-based):
  `omacom/omarchy#8672` and `omacom/omarchy-iso#129`. Plus a community port,
  `bprendie/omarchy-snapdragon`, with downloadable ISOs. Machines covered:
  ThinkPad T14s Gen 6, HP, ASUS A16/A14, Yoga Slim 7x, Surface Laptop 8.
  **No Samsung, and nobody working on one.**

  Architectural note: the community port is Arch userspace on an **Ubuntu
  kernel** (`7.2.0-18-qcom-x1e`). So "port this to Arch" really means "which
  kernel carries the Samsung drivers", and today the answer is only Anatase's.
- `mtssoh/nixos-samsung-galaxy-book4edge` — NixOS, early.
- `Nehal-aditya/book4-edge-kali`, `-kali-live` — Kali, early.

## So what is actually ours

Ranked by confidence, after the survey.

**Almost certainly new:**

1. **The keyboard backlight EC command.** Nobody else has backlight, and
   ciscobugger's command table documents only the space above `0x80` while ours
   sits below it.
2. **Two bugs in Anatase's battery driver**: `KB9058_CYCLES` points at `0xd0`,
   which on this unit holds the state of charge; and `CAPACITY` is computed
   from charge_now/charge_full when the EC reports the gauge's own percentage
   at `0xa0`.
3. **Two bugs in the Saddytech driver** (swapped capacities, rate sign).
4. **The ath12k firmware regression**: c7-00108 fails where c5-00302 works. No
   one appears to have reported it; Anatase solved the board-id lookup with an
   alias, which is a different problem.
5. **RTC and EFI variables share one cause**, via `qcom,uefi-rtc-info` — see
   [kernel.md](kernel.md).
6. **This 14" ADSP image has no `charger_pd`**, with the per-model contrast
   against the 15.6" now established.

**Probably new, worth checking before claiming:** the UCM profile and mic gains,
the `chain.mod` trick for a Windows entry under Fedora's signed GRUB, the GRUB
update guard, and the second undescribed WSA883x per speaker bus.

**Not ours, and credited as such:** the EC protocol itself, the device tree, the
keyboard udev rule, and reading the Bluetooth address out of the Windows
registry. See [CREDITS.md](../CREDITS.md).

## The most useful thing to do next

Open an issue on `ciscobugger/book4-edge-linux`. Same machine family,
complementary gaps: they have the camera and a deeper EC decode, we have the
backlight command and the 14". That exchange moves both repositories the same
day, which no mailing list will.
