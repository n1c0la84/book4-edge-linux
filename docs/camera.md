# Webcam (not working yet)

No device tree describes the 14" camera. Findings so far (1 October 2026),
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
