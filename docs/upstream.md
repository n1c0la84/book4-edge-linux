# Things to report upstream

## To Anatase (`ene-kb9058-battery`, `samsung-emuec`)

1. **PD request after hot plug times out.** **Reported 1 October 2026 with the
   patch: https://github.com/anatase-org/kernel-anatase/issues/1** (their
   process: issues with patches in kernel-anatase; patchwork closes PRs). `samsung_emuec_request_pdo()` is
   sent before the S2MM006 has settled; it times out (-110) and is never
   retried (`pd_attempted`), leaving the charger at 5 V. Repeating it ~1 s later
   succeeds. Patch: [drivers/anatase/patches/0001](../drivers/anatase/patches).
   Compared on 1 October with ciscobugger's 17 September fix for the 15.6", a
   user-space daemon: it builds its own Request (which `samsung-emuec` already
   does) and retries at most twice, 30 s apart. A 1 s retry inside the driver
   is enough on the 14", so our patch stands; credit them for finding it first.
   Not a discovery: ciscobugger reached the same conclusion two weeks earlier on
   their own driver for the 15.6" ("stage the PD request ourselves", 17 Sept).
   It is still a real fix to *this* driver, and worth sending as one.
2. **Cycle count reads the wrong register.** `KB9058_CYCLES` is `0xd0`, but on
   this 14" unit EC space `0xd0..0xd1` holds the state of charge (`00 62` = 98
   while the gauge at `0xa0` read 98 %). The BIX-style block at `0xb0..0xb7` is
   design capacity, last full, design voltage and an unidentified word at
   `0xb6` (`00 25` = 37): a cycle-count candidate, unproven.
3. `CAPACITY` is computed from charge_now / charge_full; the EC also reports the
   gauge's own percentage at `0xa0` (big-endian u16).

## To the other community driver (Saddytech, recommended in zensanp/linux-book4-edge#4)

- Design and last-full capacity are swapped (`design = af[2..3]`,
  `full = af[0..1]`); per `BATC._BIX` and the hardware, design is the lower word
  (`0xb0`), last full the upper (`0xb2`).
- The rate is cast to `s16`; the EC reports an unsigned magnitude (seen: 228 mA
  on AC, 558 mA discharging, never >= 0x8000) and the direction is in the state
  byte at `0x84` (bit 0 discharging, bit 1 charging).

## To ath12k / linux-firmware

- WCN7850 `17cb:1107` subsystem `17cb:1107`: firmware c7-00108 fails where
  c5-00302 works (details in [firmware.md](firmware.md)); not reported by
  anyone we know of. Anatase solved the board-id 255 lookup with an alias in
  their linux-firmware fork.

## To systemd / libinput

- The ENE KB9058 keyboard (`hid-over-i2c 0CF2:9050`) is tagged as a tablet pad
  by `input_id`; libinput binds it as a pad and no keys reach the session.
  Anatase carries a kernel HID quirk; a udev hwdb entry would help every distro.

## To the linux-arm-msm DTS thread

- `pmic-glink` / `qcom_battmgr` cannot work **with this 14" unit's firmware**:
  Samsung's ADSP image has no `charger_pd` (verified against Dell/Lenovo X1E
  images and the Windows driver store, where the battery is ACPI `PNP0C0A` via
  the EC). The Anatase DTS already drops it.

  **Scope correction (1 Oct).** This is a property of the firmware image, not of
  the product line. ciscobugger's 15.6" (NP750XQA, X1P42100) ships a
  `battmgr.jsn` in its ADSP firmware set, so that model *does* run the charger
  protection domain. Any report should say "this firmware image" and not "the
  Book4 Edge", or it will be contradicted by the next owner who checks.

## To ciscobugger (`ciscobugger/book4-edge-linux`, 15.6" NP750XQA)

Not a bug report — an exchange. Their repository and this one cover the same
machine family from opposite ends. See [related-work.md](related-work.md).

- **We can offer**: the keyboard backlight EC command (`{0x10, x, level}` at
  address `0x62`), which sits in the sub-`0x80` command space their `EC2.sys`
  table does not cover; the 14"/X1E80100 device tree and firmware set; the
  ath12k c5/c7 firmware finding; and the ADSP `charger_pd` contrast between the
  two models.
- **We would like**: whether their camera sensor (OV02C10) is also the one in
  the 14", and how they identified it; their EC command table applied to our
  backlight blinking problem; and the charging command namespace
  (`CMD_CHG_CUR` etc.), which may allow a charge limit.
