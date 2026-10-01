# Things to report upstream

## To Anatase (`ene-kb9058-battery`, `samsung-emuec`)

1. **PD request after hot plug times out.** `samsung_emuec_request_pdo()` is
   sent before the S2MM006 has settled; it times out (-110) and is never
   retried (`pd_attempted`), leaving the charger at 5 V. Repeating it ~1 s later
   succeeds. Patch: [drivers/anatase/patches/0001](../drivers/anatase/patches).
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

- `pmic-glink` / `qcom_battmgr` cannot work on this machine: Samsung's ADSP
  image has no `charger_pd` (verified against Dell/Lenovo X1E images and the
  Windows driver store, where the battery is ACPI `PNP0C0A` via the EC). The
  Anatase DTS already drops it.
