# Linux handoff: fingerprint reader (controller disabled in our DTB)

Written 8 October 2026 in Windows, for a Claude Code session on Fedora or
Arch on the same machine (14", NP940XMA).

## What Windows shows

- Sensor: **EgisTec Touch Fingerprint Sensor, USB `1c7a:05a1`**, a
  match-on-chip sensor. libfprint's `egismoc` driver lists `05a1` and ships
  test captures for it (`tests/egismoc-05a1/`).
- Bus: hub port 0 (`ACPI(_SB_)#ACPI(USB4)#ACPI(RHUB)#ACPI(PRT0)`) of the
  xHCI controller **`\_SB.USB4`** (`QCOM0D09`, `_UID` 4).
- `\_SB.USB4._CRS` (DSDT from `C:\Users\nicol\Downloads\acpidump\dsdt.dat`):
  - registers at **`0x0a200000`**, length 0x100000;
  - interrupts 272, 277, 556, 557 (GIC SPI 240, 245, 524, 525);
  - one `GpioIo` on `\_SB.GIO0` (TLMM), **pin 184**, output only, pull-up:
    probably the sensor's power or reset line. Whether Windows drives it
    high or low is not known.
- The separate `Samsung FPHelper Device` (`ACPI\SAMM0615`) is a Samsung
  helper; the sensor itself is the plain USB device.

## What Linux has

Our DTB (`dts/x1e80100-samsung-galaxy-book4-edge-14.book4-own.dtb`):

| node | status |
|---|---|
| `/soc@0/usb@a000000` | disabled |
| **`/soc@0/usb@a200000`** | **disabled** |
| `/soc@0/usb@a400000` | okay |
| `/soc@0/usb@a600000` | okay |
| `/soc@0/usb@a800000` | okay |

`usb@a200000` is `usb_2` in `x1e80100.dtsi`. That is why Linux sees no
fingerprint reader at all.

## Steps

1. In the board DTS, enable `&usb_2` with its high-speed PHY
   (`&usb_2_hsphy`) and whatever eUSB2 repeater that PHY needs. Copy the
   pattern from mainline X1E boards that enable `usb_2` (`grep -l
   '&usb_2 ' arch/arm64/boot/dts/qcom/x1*.dts`). Whether this board has a
   repeater on that port is unknown (no schematic): try without one first.
2. If the device does not enumerate, add a fixed regulator or `gpio-hog`
   on **TLMM 184** (try output high first), and check that 184 is not in
   `gpio-reserved-ranges`.
3. Boot with the new DTB as a separate GRUB entry (as with
   `install/gpio44-test.sh`), then `lsusb | grep 1c7a`.
4. `fprintd-enroll` / `fprintd-verify` (libfprint with `egismoc`; check
   the distribution's version lists `05a1`).
5. Record in `docs/TODO.md` and, if it works, add the DT change to
   `dts/patches/` and offer it to Anatase.
