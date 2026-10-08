# Samsung Galaxy Book4 Edge EC protocol (from Windows EC2.sys)

Source: `EC2.sys` (ec2.inf, ACPI\SAM060B), 66608 bytes, sha256
2b4c7b2deaa4b654d574fbecdd15e24a95f39bdc99301b577e61833faafed9dd.
Disassembled with binutils `objdump -d` (pei-aarch64-little); `annotate.py` resolves
string and import references into `EC2.ann`.

## Transport (I2C, SPB IOCTL 0x41808 = function 0x602, execute-sequence)
Address: ACPI ECTC declares 0x62 on \_SB.I2C6 (b94000, disabled in our DT) and
0x64 on \_SB.I2C1 (b80000, the keyboard bus). Try 0x64 first.

| op | bytes on the wire | code |
|---|---|---|
| XDATA read  | write `30 00 HI LO`, repeated-start read 2 -> `50 VAL` | EneEcReadMbox @ 0x140006028 |
| XDATA write | write `40 00 HI LO VAL` | EneEcWriteMbox @ 0x1400060d0 |

## EC-space mailbox (in XDATA)
| XDATA | meaning |
|---|---|
| FF10 | command: 0x88 = read EC space, 0x89 = write EC space; 0 = idle |
| F480 | EC-space offset; read result is returned here |
| F481 | value for writes |
| F49F | slot bitmap (who holds the mailbox) |
| F49E | collision bitmap |

Read (SecEne9058KbcReadEcSpace @ 0x140006ab0), retried until no collision:
wait FF10==0 (<=30 x 1 ms) -> slot = GetSlotIdx -> F480=off -> FF10=0x88 ->
wait FF10==0 -> val=F480 -> dirty=CheckSlotDirty(slot) -> ClearSlotIdx(slot).
Write (SecEne9058KbcWriteEcSpace @ 0x1400069e8): same, F480=off, F481=val, FF10=0x89,
no idle wait after the command.

GetSlotIdx @ 0x140006160: a=F49F, b=F49E; if a!=b: F49E=a; first clear bit i of a; F49F=a|1<<i.
CheckSlotDirty @ 0x140006370: F49E & 1<<i.  ClearSlotIdx @ 0x140006280: clear bit i in F49F and F49E.

## ACPI regions handled by EC2.sys
- 0xA1 "EcSpace" (ECR under ECTC): offset = EC-space offset. Battery fields per DSDT:
  0x78 PBTE, 0x80 B1EX(b0)/ACEX(b2), 0x84 B1ST, 0xA0 B1RR, 0xA4 B1PV, 0xB0 B1AF, 0xB4 B1VL, 0xC0 CTMP.
  _BST: remaining capacity = byteswap16(B1RR >> 16), voltage = byteswap16(B1PV & 0xffff); 0xFFFF = unknown.
- Two more RegisterOpRegionHandler calls (likely 0xA0 MCU1 / 0xA2 EXTC mailbox); not decoded yet.
- 0x9C EMOP (Type-C) and 0x9E BMOP (gauge) belong to EMEC (SAM0604) - different driver, not in the store.

## Status
CONFIRMED ON HARDWARE 30 Sept 2026 (bus i2c-2 = b80000, addr 0x64), on AC at 100 %:
probe: FF10/F49F/F49E/F481 -> 50 00, F480 -> 50 c0 (all status 0x50).
battery: 0x80=05 (B1EX=1, ACEX=1), B1ST=00, B1RR=100e6400, B1PV=6e45eb00,
B1AF=100ecb0d, B1VL=2500a03c, CTMP=0. Each u32 = two byte-swapped (big-endian) u16 halves:
- B1RR: low 100 (= percent?), high 3600 (remaining, mAh)
- B1PV: low 235 (rate, mA?), high 17774 (voltage mV; 4S at 4.44 V/cell)
- B1AF: low 3531, high 3600 (last-full / design?)
- B1VL: low 15520 (design mV), high 37 (cycle count?)
3600 mAh x 15.52 V = 55.9 Wh = rated capacity of the 14" model (from memory; verify).
Field mapping per DSDT _BST/SBIX (from the workstation session), CONFIRMED by an unplug test:
| | on AC | unplugged ~1 min |
|---|---|---|
| 0x80 ACEX | 1 | 0 |
| B1ST 0x84 | 00 idle | 01 discharging |
| B1PV low (rate) | +228 mA | +558 mA |
| B1PV high (voltage) | 17772 mV | 17598 mV |
| B1AF low (design) | 3531 | 3531 |
| B1AF high (last full) / B1RR high (remaining) | 3600 / 3600 | 3600 / 3600 |
- Rate is an UNSIGNED magnitude; direction comes from B1ST (bit0 discharging, bit1 charging),
  as ACPI _BST defines it. Driver: CURRENT_NOW = -rate when discharging.
- B1VL low = design voltage 15520 mV. B1RR low (=100) and B1VL high (=37) still unknown.
- Remaining did not drop in 1 min (~9 mAh expected): EC updates capacity in coarse steps.

## EC events (the likely cause of "no charging after a hot replug")
- ACPI never writes MCU1 CBDT/BTPT (SCDT/SBTP defined but uncalled), so the 0xA0 handler's writes
  (ext cmds 0x06 / 0x0D) never happen on this machine; its only read is PSRC = EC-space 0x80.
- EC2.sys interrupt work item (0x1400073a0): PLAIN 12-byte I2C read (no register write) on the "raw"
  SPB target (ctx+0xB0), function 0x1400036c8. byte0 = type: 1 hotkey (byte2 = code; FnLock,
  toggleFS01/09/10...), 4 fan trip, 5 ?, 6 OSD/helper, 7 ACPI event -> EVTQ -> _Q51/_Q52 (charger).
  Raw-target writes (queued items {cmd, hi, lo}) go through 0x140003818 on the same target.
- Mailbox traffic uses a different target (ctx+0xB8, via 0x140006be0).
- 30 Sept test: plain 12-byte read from 0x64 on b80000 -> ENXIO (NACK). So the raw/event target is
  very likely 0x62 on \_SB.I2C6 = b94000 (listed FIRST in ECTC _CRS), which is DISABLED in our DT.
  Not yet proven from the disassembly (the resource-index -> target mapping is unverified).
- Linux has never drained this queue. Hypothesis: the charger attach event can't be delivered/acted on
  while earlier events sit unread. Next: enable i2c@b94000 in the DTS (status okay; check pinctrl),
  rebuild DTB (dtc -p 8192), boot it as a SEPARATE menu entry first, then `ectool.py events` on 0x62.
- Extended commands: cmd >= 0x80 written to FF10, params at F480+, per-command in/out lengths in a
  table at .data 0x14000c5a0 (4 bytes each); 0x88/0x89 (EC-space read/write) are two of them.

## BYTE-LEVEL MAP (authoritative; values are BIG-ENDIAN u16 at each offset)
ectool prints u32s assembled little-endian (byte off+0 lowest), shown MSB first, so
"A0=100e6400" means bytes A0=00 A1=64 A2=0e A3=10. Do NOT read the printed hex as byte order.
| offset | bytes (AC run) | value | meaning |
|---|---|---|---|
| 0xA0 | 00 64 | 100 | state of charge, % |
| 0xA2 | 0e 10 | 3600 | remaining capacity, mAh (_BST from B1RR high half) |
| 0xA4 | 00 eb | 235 | rate, mA, unsigned; direction from B1ST (558 unplugged) |
| 0xA6 | 45 6e | 17774 | voltage, mV (17598 unplugged) |
| 0xB0 | 0d cb | 3531 | design capacity, mAh (ACPI low half of B1AF) |
| 0xB2 | 0e 10 | 3600 | last full charge capacity, mAh |
| 0xB4 | 3c a0 | 15520 | design voltage, mV |
| 0xB6 | 00 25 | 37 | unknown; **not** the cycle count (see 0xD0) |
| 0xD0 | | | cycle count (`CYLC`, read by `_BIX`); Windows reports 105 on 8 Oct |
Little-endian gives garbage (0xA0 -> 25600), so big-endian is confirmed by the data.

## Wake timer (raw target 0x62), decoded 8 October 2026

From `EC2.sys` (same build, sha256 above), disassembled in Windows with
Capstone. IOCTL dispatch switch at 0x140003de0 (device type 3,
`METHOD_BUFFERED`, `FILE_ANY_ACCESS`):

| IOCTL | code | handler | bytes written |
|---|---|---|---|
| `IOCTL_START_WAKEUP` | 0x0003000C | 0x140003f88 | `02 T/60 T%60` |
| `IOCTL_START_WAKEUP_ONCE` | 0x00030010 | 0x140003f98 | `03 T/60 T%60` |
| `IOCTL_STOP_WAKEUP` | 0x00030014 | 0x140003f64 | `04 00` |

- START and ONCE share the code: a local starts at 0 (0x140003d70), START
  sets it to 2 and falls through into ONCE; `mode = (local == 0) ? 3 : local`.
- `WdfRequestRetrieveInputBuffer(min 1)`, then `T = (u8) *(u32 *)in`: only
  the **low byte** is used, so T is 0-255. Logged as `TimeOut %d (%d)`
  (byte, full value).
- Split with the constant 0x88888889 (`umull`, `>> 37` = divide by 60):
  byte 1 = T / 60, byte 2 = T % 60. So the EC takes a (larger unit, smaller
  unit) pair: minutes and seconds if T is in seconds (max 4:15), hours and
  minutes if T is in minutes (max 4 h 15). **The unit is not in the
  driver**; find it with [tools/ec/wake-timer.py](../tools/ec/wake-timer.py).
- Sent like every raw-target command: START/ONCE first through
  `I2CWriteWithWorkItemSynced` (0x140005748: lock, then the raw write
  0x140003818 on `ctx+0xB0`), then also queued on the 20-slot ring
  (0x140003470, `WriteWorkItem wData`), so the EC gets it twice. STOP is
  only queued.
- How the EC wakes the SoC (power-button-like line, EC event interrupt, ...)
  is not known: on Linux that line has to be a wakeup source for s2idle.


`IOCTL_SET_KBDBLT` queues `{0x10, timeout, level}`, `IOCTL_GET_KBDBLT` queues
`{0x11}`; both go out as plain writes on the raw target. Level 0..3. The EC
turns the light off ~3 s after each command regardless of the second byte.
Details and the failed driver attempts: [keyboard-backlight.md](keyboard-backlight.md).
