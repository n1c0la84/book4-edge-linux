# Firmware

Nothing proprietary is shipped in this repository. You need a Windows install
on the same machine (or its driver store) to extract the DSP firmware.

## ADSP / CDSP / GPU (from Windows)

Copy from `C:\Windows\System32\DriverStore\FileRepository\` to
`/usr/lib/firmware/qcom/x1e80100/SAMSUNG/galaxy-book4-edge/`:

| file | Windows driver package |
|---|---|
| `qcadsp8380.mbn`, `adsp_dtbs.elf` | `qcsubsys_ext_adsp8380.inf_arm64_*` |
| `qccdsp8380.mbn`, `cdsp_dtbs.elf` | `qcnspmcdm_ext_cdsp8380.inf_arm64_*` |
| `qcdxkmsuc8380.mbn` | `qcdx8380.inf_arm64_*` |

`qcom_q6v5_pas` asks for the ADSP/CDSP images very early and gives up for good
if they are missing, so they must be inside the initramfs
([`userspace/initcpio/book4.conf`](../userspace/initcpio/book4.conf) on Arch;
legacy Fedora dracut: [`userspace/dracut/book4-fw.conf`](../userspace/dracut/book4-fw.conf)).

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

Early in the bring-up, `modprobe -r ath12k` or PCI remove/rescan after the
card had a QMI session panicked in `ath12k_qmi_phy_cap_send`. With c5-00302
and 7.2.7 (16 October) a PCI remove of `0004:01:00.0` and a rescan of
`0004:00:00.0` work: no panic, Wi-Fi reconnected within 25 s (the MAC
address changes across the reload). If Wi-Fi misbehaves, reboot.
`cma=256M` on the kernel command line is required (it cleared an ath12k DMA failure).

## Package (updated 26 November 2026)

`book4-edge-firmware` (`packages/book4-edge-firmware`) installs everything
above into `/usr/lib/firmware/updates/` plus EL2 and sensor files:
- ADSP, CDSP (`qcnspmcdm_ext_cdsp8380`) and GPU zap images from Windows'
  DriverStore;
- `tcblaunch.exe` (build `10.0.26100.9616` from `WinSxS`, installed to
  `/usr/lib/book4/tcblaunch.exe`, copied to `/efi` by `book4-el2`);
- 157 ambient light sensor config and registry files from
  `qcsensorsconfigcrd8380` and `System32/drivers/DriverData` (installed to
  `/usr/share/book4/sensors/`, [sensors.md](sensors.md));
- `gen70500_sqe.fw` (from `linux-firmware-qcom` on a fresh install) and the
  four Wi-Fi `c5-00302` files (`amss.bin`, `m3.bin`, `board.bin`, `board-2.bin`);
- the audio topology symlink to `X1E80100-CRD-tplg.bin`.

It is built locally and never published: `install/arch/firmware-stage.sh`
stages the files in `~/.local/share/book4-edge-firmware` (Windows `sda3`
mounted read-only; pass `BOOK4_FW_LOCAL=<dir>` on a fresh install for the four
`ath12k` `c5-00302` files), picking each by its checksum in
`packages/book4-edge-firmware/sha256sums.txt`.
