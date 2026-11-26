# Things to report upstream

## Recent upstream activity (17–26 November 2026)

- **`qcom_tsens` initramfs deferred-probe crash (`birkskyum/arewearmyet#10`,
  linux-pm / lore):** root cause reported 23 Nov (`init_common` marked
  `__init` in `drivers/thermal/qcom/tsens.c`); Christian Schmidbauer's fix
  tested on `linux-omarchy` 7.3-79 and `Tested-by` sent to lore on 25 Nov.
- **Omarchy Snapdragon (`omacom/omarchy#15860`, `birkskyum/arewearmyet#10`):**
  14" `hw-test` report sent 23 Nov; `qcom_aoss` `val:` format fix credited for
  upstream; memlat/boost/capacity/95 °C performance notes posted 17 Nov;
  speaker side correction (`swr0` = left, `swr3` = right) posted 17 Nov.
- **`jglathe/linux_ms_dev_kit#102`:** replied 22 Nov (`qcom_adsp_pwr_lmts`
  crash, LPASS macro fixes, ~0.70 W EL2 numbers; syscon fix credited).
- **Unsent upstream drafts (owner review):**
  - `docs/upstream-drafts/2026-11-soundwire-clash.txt` (SoundWire clash,
    `wsa883x` `suppress_bind_attrs`, `qcom_swrm_remove` IRQ race & re-probe
    IRQ type mismatch; needs retest on untainted kernel)
  - `docs/upstream-drafts/2026-11-usb-resume.txt` (xHCI death on `usb_2`, QMP
    combo PHY init timeout & pipe-clock unwind warning; needs retest on
    untainted kernel)
  - `docs/drafts/2026-11-14-linux-arm-msm-el1-s2idle-cntv.txt` (EL1 s2idle
    CNTV arming)
  - `docs/drafts/2026-11-16-launchpad-2084591-14inch.txt` (keyboard tablet-pad
    quirk)

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
1b. **Front camera and privacy LED (14").** Device tree patches sent
   2 October: https://github.com/anatase-org/kernel-anatase/issues/2
1c. **Charger unplugged during sleep resets the machine.** Patch sent
   4 October: https://github.com/anatase-org/kernel-anatase/issues/3
   (applies to `anatase-7.2` on its own; ours is `drivers/anatase/patches/0002`).
   Follow-up 5 October, wake for a charger plugged in during sleep (ours:
   `patches/0003`): https://github.com/anatase-org/kernel-anatase/issues/3#issuecomment-5992214169
1d. **Tweeters (four speakers), device tree.** Sent 5 October:
   https://github.com/anatase-org/kernel-anatase/issues/4
   ([dts/patches/0003](../dts/patches)). Offered: a follow-up renaming the
   swapped woofer prefixes to `WooferLeft`/`WooferRight`.
1e. **Fingerprint reader on `usb_2`, device tree.** Sent 8 October:
   https://github.com/anatase-org/kernel-anatase/issues/5 (standalone on
   `anatase-7.2`; ours, on top of the tweeters, is `dts/patches/0004`).
1f. **Type-C orientation from the CC pin (samsung-emuec).** Sent 10 October:
   https://github.com/anatase-org/kernel-anatase/issues/6 (standalone on
   `anatase-7.2`; ours is `drivers/anatase/patches/0004`). Asks how port 0
   maps to the DP controllers (monitor still fails on AUX).
2. ~~Cycle count reads the wrong register~~: wrong, do not send. The DSDT's
   `_BIX` reads `CYLC` at EC 0xD0 (TODO.md, 8 October), which is what the
   driver reads; Windows' sleep study reported 137 cycles on 16 November.
3. `CAPACITY` is computed from charge_now / charge_full; the EC also reports the
   gauge's own percentage at `0xa0` (big-endian u16).

**Not reported yet (checked 17 November):** woofer prefixes named by side
(`dts/patches/0005`; only offered in #4), the absent `eusb5_repeater` at 0x43
(`dts/patches/0006`), refreshing the battery on read
(`patches-galaxybook-ec/0001`; his reworked driver still serves the cached
values), and the panel supply chain without `regulator-always-on`
(sleep-backport 0018, a sleep-power fix). All four were posted, with the comparison of his rework against our patches,
on 17 November: https://github.com/anatase-org/kernel-anatase/issues/1#issuecomment-6943264160

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

## To linux-arm-msm

- **s2idle at EL1 under Gunyah needs CNTV armed, unmasked** (13 November
  2026, [TODO.md](TODO.md) CL5/DRIPS item). Draft reply to Michael Burch's
  thread of 8 October ("x1e80100: no AOSD/CXSD in suspend ..."):
  [drafts/2026-11-14-linux-arm-msm-el1-s2idle-cntv.txt](drafts/2026-11-14-linux-arm-msm-el1-s2idle-cntv.txt).
  Not sent: the owner sends it (plain text). The kernel-patch route
  (sleep-backport 0045 as an RFC) is parked: it needs a kernel build that
  replaces the daily kernel, and `deep` works without it.

