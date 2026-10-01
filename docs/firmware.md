# Firmware

Nothing proprietary is shipped in this repository. You need a Windows install
on the same machine (or its driver store) to extract the DSP firmware.

## ADSP / CDSP / GPU (from Windows)

Copy from `C:\Windows\System32\DriverStore\FileRepository\` to
`/usr/lib/firmware/qcom/x1e80100/SAMSUNG/galaxy-book4-edge/`:

| file | Windows driver package |
|---|---|
| `qcadsp8380.mbn`, `adsp_dtbs.elf` | `qcsubsys_ext_adsp8380.inf_arm64_*` |
| `qccdsp8380.mbn`, `cdsp_dtbs.elf` | `qcsubsys_ext_cdsp8380.inf_arm64_*` |
| `qcdxkmsuc8380.mbn` | probably `qcdx8380.inf_arm64_*` (not re-checked) |

`qcom_q6v5_pas` asks for the ADSP/CDSP images very early and gives up for good
if they are missing, so they must be inside the initramfs:
[`userspace/dracut/book4-fw.conf`](../userspace/dracut/book4-fw.conf).

Note: Samsung's ADSP image has **no charger PD** (`charger_pd`), unlike Dell or
Lenovo X1E images. That is why `qcom_battmgr` / `pmic_glink` can never work on
this machine: battery and charging go through the ENE EC and the S2MM006 Type-C
controllers instead. See [ec-protocol.md](ec-protocol.md).

## Wi-Fi (WCN7850, ath12k)

The card is `17cb:1107`, subsystem `17cb:1107`, `qmi-board-id=255`.

- Upstream `board-2.bin` has no entry for this subsystem at board-id 255, so the
  api-1 fallback `board.bin` is used. A `board.bin` taken from the upstream
  entry for subsystem 1107 / board-id 82 works.
- Firmware **c7-00108** from current linux-firmware does **not** work on this
  card. **c5-00302** (Debian `firmware-atheros` 20251111-1) works.

Files go in `/usr/lib/firmware/ath12k/WCN7850/hw2.0/` (`amss.bin`, `m3.bin`,
`board.bin`). Check with:

    strings /usr/lib/firmware/ath12k/WCN7850/hw2.0/amss.bin | grep c5-00302

Never `modprobe -r ath12k` or PCI remove/rescan after the card has had a QMI
session: it panics in `ath12k_qmi_phy_cap_send`. If Wi-Fi misbehaves, reboot.
`cma=256M` on the kernel command line is required (it cleared an ath12k DMA failure).
