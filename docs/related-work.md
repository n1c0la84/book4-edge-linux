# Related work, and what is actually ours

Surveyed 1 October 2026. This machine has more people working on it than it
looks, and several of them are ahead of us in places. Knowing who has what
avoids reporting things that are already known — and avoids missing things we
could simply take.

## The projects

### Anatase — `anatase-org/patchwork`, branch `anatase-7.2`

The active upstream for this laptop. A Fedora ARK kernel tree carrying:

- `drivers/platform/arm64/samsung-galaxybook-ec.c` — a **full EC platform
  driver**. Until 30 September this was `drivers/power/supply/ene-kb9058-battery.c`
  and did battery only; it now also drives the **keyboard backlight** (via the
  `0xFF10` mailbox, commands `0xfc`/`0xfd`), the backlight hotkey and fan
  platform profiles. `CONFIG_EC_SAMSUNG_GALAXYBOOK`.
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

The battery driver recommended in `zensanp/linux-book4-edge#4`. Same EC protocol, two bugs we can show:
design/last-full swapped, and the rate cast to `s16` when the EC reports an
unsigned magnitude. Details in [upstream.md](upstream.md).

### zensanp — `zensanp/linux-book4-edge`

The community issue tracker for this laptop. Issue #3 is Wi-Fi, #4 battery, #8
USB-C and audio. The maintainer reports a 14" too.

## Other distributions

- **Omarchy Dragon** — official Snapdragon X support for Omarchy (Arch-based):
  `omacom/omarchy#8672` and `omacom/omarchy-iso#129`. Plus a community port,
  `bprendie/omarchy-snapdragon`, with downloadable ISOs. Machines covered:
  ThinkPad T14s Gen 6, HP, ASUS A16/A14, Yoga Slim 7x, Surface Laptop 8.
  No Samsung among the machines listed (as of 1 October 2026).

  Architectural note: the community port is Arch userspace on an **Ubuntu
  kernel** (`7.2.0-18-qcom-x1e`). So "port this to Arch" really means "which
  kernel carries the Samsung drivers", and today the answer is only Anatase's.
  **Update 9 November 2026: Samsung is covered now.** The tracker
  arewearmyet.com (repo `birkskyum/arewearmyet`) lists the 14" as
  "Bootable: Problems": the stock 4.5.0rc1 image resets in a loop (no tree);
  with an owner's board package (`hegjon/omarchy-galaxy-book4-edge`, an
  NP944XMA, Omarchy team) it runs daily on linux-omarchy 7.3 with the **v8
  device-tree series** posted to linux-arm-msm (mstoretv, 30 September;
  copy in the tracker's `device-trees/samsung-galaxy-book4-edge-14/`).
  Tree, hardware IDs and firmware (`samsung-galaxy-book4-edge-firmware`)
  are on Omarchy's edge channel; firmware not in linux-firmware.
  Hardware IDs: `ubuntu/stubble#98` (open) takes only IDs that include
  the BIOS version or baseboard `NP944XMA-MC1US`. This machine reports
  baseboard `NP940XMA-KB1IT` (European model), SKU `GALAXY A5A5-PAKY`, BIOS
  P00AKY.053. Checked 9 November: **none of the PR's six IDs match this machine**,
  so the stock image won't pick the tree on an NP940XMA. `systemd-analyze chid`
  gives the IDs without root (no fwupd needed); the baseboard ones are
  `8fc369d5-d5a6-54b7-84a2-2c26ca106430` (MFPS+mp), `0569ad99-d9c0-586c-bd74-3871407fe316`
  (MS+mp), `8f53b329-2c93-50a5-9fef-2602b9f58565` (MP+mp).
  **Posted 9 November** (owner's OK): the IDs on
  [stubble#98](https://github.com/ubuntu/stubble/pull/98#issuecomment-6750168776),
  the model report [birkskyum/arewearmyet#10](https://github.com/birkskyum/arewearmyet/issues/10)
  (fwupdtool output, what works), and our status (sleep, DC ZVA fix, EC PD
  fix, speakers, offer to test) on the Omarchy Book4 Edge thread
  [omacom/omarchy#15860](https://github.com/omacom/omarchy/discussions/15860#discussioncomment-19501222).
  Watch those three for replies. The 15" row notes charging stuck at 5 V
  without a userspace tool (`book4-pd-charge`); our kernel-side PD fix
  ([ec-protocol.md](ec-protocol.md)) is the same problem.
- `mtssoh/nixos-samsung-galaxy-book4edge` — NixOS, early.
- `Nehal-aditya/book4-edge-kali`, `-kali-live` — Kali, early.

## So what is actually ours

Ranked by confidence, after the survey.

**Still ours, verified 1 October against their current tree:**

1. **The `samsung-emuec` PD retry fix.** Checked: `pd_attempted` is still a
   `bool` set once, so the bug is live in their tree and the patch is still
   wanted. ciscobugger reached the same conclusion first on their own driver,
   so present it as a fix rather than a finding.
2. **Two bugs in the Saddytech driver** (swapped capacities, rate sign). That
   repository has not changed since 17 August and is the one most people run.
3. **The ath12k firmware regression** — see below.

**Overtaken on 30 September:**

- **The keyboard backlight.** Anatase's new EC driver implements it and it
  works, through the `0xFF10` mailbox on address `0x64` (`{0x40, 0x00, 0xff,
  0x10, 0xfd}` to write, `0xfc` to read). Our command — `{0x10, x, level}` at
  address `0x62` — is a genuinely different mechanism on the event channel, and
  the discovery stands; but theirs works where ours blinks, so there is nothing
  left to contribute here except, perhaps, an explanation of why the other path
  misbehaves.
- **The two battery-driver bugs** (`KB9058_CYCLES` at `0xd0`, `CAPACITY`
  computed rather than read from `0xa0`). The driver was rewritten as a platform
  EC driver; re-check against `samsung-galaxybook-ec.c` before reporting
  anything.
- **The EC event interface at `0x62`**, which we were chasing, is now described
  in their device tree as `samsung,galaxybook4-edge-ec-events`, owned by the
  mailbox driver.
- **`usb_mp` is now 16-inch only** in their DTS, which was our observation.
4. **The ath12k firmware regression**: c7-00108 fails where c5-00302 works. No
   one appears to have reported it; Anatase solved the board-id lookup with an
   alias, which is a different problem.
5. **RTC and EFI variables share one cause**, via `qcom,uefi-rtc-info` — see
   [kernel.md](kernel.md).
6. **This 14" ADSP image has no `charger_pd`**, with the per-model contrast
   against the 15.6" now established.

**The one thing nobody else has:** a **Fedora** integration. Anatase ships its
own distribution; ciscobugger's repository is Arch-shaped (mkinitcpio,
systemd-boot). The GRUB guard, the `chain.mod` Windows entry, the dnf hooks and
the update-safety analysis in this repository are the only ones that exist for
this machine on Fedora. That is integration rather than discovery, and it is
still the reason this repository is worth keeping.

**Probably new, worth checking before claiming:** the UCM profile and mic gains,
the `chain.mod` trick for a Windows entry under Fedora's signed GRUB, the GRUB
update guard, and the second undescribed WSA883x per speaker bus.

**Not ours, and credited as such:** the EC protocol itself, the device tree, the
keyboard udev rule, and reading the Bluetooth address out of the Windows
registry. See [CREDITS.md](../CREDITS.md).

## The most useful thing to do next

**Omarchy Dragon** is the clearest unoccupied space — see [omarchy.md](omarchy.md).
We found no Samsung among the machines in their public threads (1 October 2026),
and we have a working one.

Then: open an issue on `ciscobugger/book4-edge-linux`. Same machine family,
complementary gaps: they have the camera and a deeper EC decode, we have the
backlight command and the 14". That exchange moves both repositories the same
day, which no mailing list will.

- **14 November 2026, omarchy#15860:** camotim (15" NP750XQB, Omarchy edge
  image) reported the keyboard tagged as a tablet pad and a touchpad at
  another I2C address. Replied with our cause and rule for the keyboard
  (`userspace/keyboard/99-book4-keyboard.rules`, same `0CF2:9050`):
  https://github.com/omacom/omarchy/discussions/15860#discussioncomment-19614234

