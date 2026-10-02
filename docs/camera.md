# Webcam (works, experimental)

## Status, 2 October 2026: it works

With the experimental device tree
[`dts/src/x1e80100-samsung-galaxy-book4-edge-14-camera.dts`](../dts/src/x1e80100-samsung-galaxy-book4-edge-14-camera.dts)
on the Anatase kernel (`7.2.7-book4`), the OV02C10 probes on CCI0 (it reads
its chip ID), CAMSS registers `/dev/video0`, and libcamera 0.7.2 (Fedora
`libcamera-tools`) captures frames through its software ISP:

    cam -l                     # "Internal front camera"
    cam -c1 -C5 -s pixelformat=ABGR8888 --file=frame-#.bin

1920x1092 at about 40 fps, upright, plausible colours, dark at first
(libcamera has no `ov02c10.yaml` tuning file and no sensor helper for it:
"Failed to create camera sensor helper for ov02c10").

How to try it: build the DTB in the Anatase tree (add it to
`arch/arm64/boot/dts/qcom/Makefile`, `make LOCALVERSION= qcom/<name>.dtb`),
then [`install/camera-dtb.sh`](../install/camera-dtb.sh) adds a separate
"alt DT camera.dtb" GRUB entry for the default kernel (`remove` drops it).

To make it the default (done on the reference machine on 2 October):

    echo "7.2.7-book4 /dtb-test/camera.dtb" | sudo tee /etc/book4/default-dtb
    bash install/update-boot-hook.sh

The boot hook then uses that DTB for the default kernel's main and verbose
entries and keeps the kernel's own DTB as "standard DT". The setting names the
kernel it was built for and is ignored once another kernel becomes the
default, so a newer kernel never boots with this DTB; rebuild the camera DTB
from the new tree and update the file then.

What the DTB adds to Anatase's 14" DTS: the CCI0 node and pins (from
zensanp's `hamoa.dtsi`), the legacy-binding CAMSS node from the kernel's
`qcom,x1e80100-camss.yaml` example, the sensor on `cci0_i2c0` with MCLK4 on
gpio100, reset gpio109, supplies `l7b`/`l10b`, CSIPHY0 supplies `l2c`/`l1c`,
GPIO hogs 96, 99, 221, 225 (after zensanp's and ciscobugger's trees), and the
privacy LED on TLMM 110 (below).

Pitfall: the binding example gives the CSIPHY register regions 0x1000; the
driver writes above that and the first capture oopsed in `csiphy_reset`.
0x2000 (as in zensanp's `hamoa.dtsi`) works.

## Privacy LED: TLMM GPIO 110

The first captures ran with the LED next to the camera **off**: nothing in the
sensor's power path drives it. Windows has a separate file for it,
`CAMP_PRLD_QRD.bin` ("Privacy LED binary file", `qccamplatform_ext8380`),
holding a single entry `0x0506` whose encoding we have not decoded. The Dell
XPS 13 9345 DTS drives its camera indicator from TLMM 110; driving TLMM 110
high here lights the LED (2 October).

The DTB declares it as a `gpio-leds` LED (`white:camera-indicator`, default
off) and links it to the sensor with `leds = <&cam_privacy_led>;
led-names = "privacy";`. The V4L2 core then switches it on when the sensor
starts streaming and off when it stops: verified on the 14" (brightness 1
while streaming, 0 after, LED seen on and off).

The LED is a GPIO the CPU controls, not hard-wired to the sensor's power, so
it only protects as long as the kernel's own logic does. Treat it as an
indicator, not a hardware guarantee.

Sent to Anatase on 2 October as two device tree patches (CCI0 + CAMSS in
`hamoa.dtsi`, disabled; the camera and LED in the 14" DTS):
https://github.com/anatase-org/kernel-anatase/issues/2 . Copies in
[`dts/patches/`](../dts/patches). They are functionally identical to the
tested DTB apart from three empty CAMSS port nodes.

Still to do: tuning/sensor helper in libcamera (ciscobugger has one), test in
a browser and PipeWire, check the GPIO hogs against power use (they keep the
sensor powered permanently).

## Background

Before this, no device tree described the 14" camera. Findings so far (1 October 2026),
from the Windows driver store and the X1E80100 pin table.

## Sensor: OmniVision OV02C10, I2C 0x36

- `qccamfrontsensor_extension8380.inf` labels
  `com.qti.sensormodule.partron_ov02c10.bin` "for NX (8380)" / "for Samsung
  NX16 (8380)"; the other modules there (Sunny IMX688, Shinetech OV08X) are
  labelled "Hamoa", Qualcomm's reference designs. Samsung's 14" codename is
  NX14 (the driver store has `qcacsp_ss8380_nx14`).
- This machine enumerates its Qualcomm devices as `SUBSYS_CRD08380`
  (Windows registry), which selects the `_QRD` sections of the INF:
  `SCFG_FRONT_QRD.bin` names `partron_ov02c10` and the 8-bit I2C address
  `0x6c` = **0x36**.
- Same sensor and address as the 15.6" (NP750XQA) in ciscobugger's tree.

## Power sequence (`CAMF_RES_QRD.bin`, device `\_SB.CAMF`)

Clocks `gcc_camera_xo_clk`, `gcc_camera_ahb_clk`, `cam_cc_cpas_ahb_clk`,
GDSC `cam_cc_titan_top_gdsc`, rail `/arc/client/rail_mmcx`, then:

    on:  GPIO101=1  GPIO102=1  GPIO109=0  GPIO99=1  (1 ms)  GPIO96=1  (1 ms)  GPIO109=1  (10 ms)
    off: GPIO109=0  GPIO101=0  GPIO102=0  (1 ms)  GPIO96=0  (1 ms)  GPIO99=0

| GPIO | X1E80100 function | role (inferred) | 15.6" (ciscobugger) |
|---|---|---|---|
| 101, 102 | `cci_i2c` | CCI0 I2C bus of the sensor | sensor on `cci0_i2c0` |
| 109 | `cci_timer0` (used as GPIO) | reset, released last | `reset-gpios = <&tlmm 109 ...>` |
| 96, 99 | `cam_mclk` (used as GPIO) | probably supply enables | not used: PMIC LDOs `l7b`, `l10b` |
| 100 | `cam_aon` | not toggled: likely the MCLK output | MCLK on gpio100 (`CAM_CC_MCLK4_CLK`) |

## What a node would need, and what is still unknown

Starting point: ciscobugger's `camera@36` node and `&camss`/`&csiphy0`
setup for the 15.6" (`dts/x1p42100-samsung-galaxy-book4-edge-np750xqa.dts`
in `ciscobugger/book4-edge-linux`), plus their OV02C10 HFLIP patch and
libcamera sensor helper.

Unknown for the 14": which supplies GPIOs 96/99 switch (fixed regulators with
`gpio` enables are the likely shape), the CSIPHY index and lane mapping, and
the module's mounting orientation. The kernel built from the Anatase tree has
`VIDEO_QCOM_CAMSS`, `I2C_QCOM_CCI` and `VIDEO_OV02C10` as modules, with X1E80100
CAMSS support.

First experiment once that kernel runs: a DT overlay with the sensor at 0x36
on `cci0_i2c0`, reset 109, MCLK4 on gpio100 and GPIOs 96/99 as fixed-regulator
enables, and see whether the OV02C10 driver reads its chip ID.
