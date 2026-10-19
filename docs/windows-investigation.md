# Investigating deep sleep from Windows

Handoff for a Claude Code session running on this laptop's Windows install.
Linux never gets the SoC into deep sleep in s2idle; Windows does (sleep
study, 8 October: hardware low power ~98 % of each standby). Every test
so far removed something on Linux and looked for a change. That finds
blockers Linux *adds*. It cannot find something Windows *does* and Linux
never does. This file sets up the opposite experiment: take things away on
Windows until DRIPS breaks.

Read first: the **Current status** block at the top of [power.md](power.md)
(one page). Then come back here.

## What is known (short)

- Windows' system deep-sleep state ("platform.DRIPS" in `\_SB.SYSM._LPI`)
  is PSCI `CPU_SUSPEND(0x0200C354)`. Qualcomm's PEP (`qcpep8380.sys`)
  registers its DRIPS callbacks on it; the entry callback only snapshots
  the AOSS sleep stats for the `NoHWDrips` check. It does no hardware setup.
- Under Windows, Hyper-V owns EL2 (launched through `tcblaunch.exe`), so
  Qualcomm's hypervisor (Gunyah/QHEE) is not running. Hyper-V passes the
  PSCI power_state through unchanged and never calls `PSCI_SET_SUSPEND_MODE`
  (decompile, `~/src/hyperv-re` on Linux).
- Linux runs at EL1 under Gunyah. There `0x0200C354` is accepted and held
  for the whole suspend, but the SoC never collapses (`aosd`/`cxsd`/`ddr`
  counters stay 0).
- Linux at EL2 (slbounce, no Gunyah): TrustZone accepts `0x0200C354` and
  returns within ~27-107 us on most calls, ~16 000 times a second. A few
  calls remain active for nearly the whole suspend. CPU 0 has pending PPI 27;
  on sampled calls from other CPUs no enabled pending interrupt was visible
  in the GIC at the SMC boundary.
- Tests that did not produce collapse individually: Linux's own RPMh votes
  (all 0 at sleep), DSPs, Secure Processor, PEP `_DSM`/GPIO 44 notifications, the
  regulators Linux never votes, and the display RSC (empty). GIC snapshots
  also found fast returns on CPUs with no visible pending enabled interrupt.

The open question is which Windows boot or standby condition permits DRIPS:
the EL2 environment, firmware mode, or a driver/PEP action are candidates.

## Ground rules for this session

- **Raw output goes to `C:\book4-windows\`, never into the repo.** Sleep
  study and energy reports contain the computer name, app names and
  sometimes network names; the repo must not contain personal data (MAC
  and IP addresses, SSIDs, user names). Linux can read that folder
  read-only (`~/mount-ro.sh`).
- Commit only extracted numbers and conclusions, in **Results** at the end
  of this file, and push.
- Ask before every change to boot configuration, BitLocker or device state,
  and say how to undo it. Never disable the PEP (`qcpep`), the ACPI bridge
  (`QCOM0427`, `qcabd`), battery/charging, storage (UFS) or the EC drivers.
- A standby test means **on battery, lid closed about 15 minutes**, then
  `powercfg /sleepstudy`. Keep chargers and USB devices the same between
  runs.
- Terminal: run Claude Code from an **administrator** PowerShell
  (`powercfg /energy`, `bcdedit`, device disabling, `wpr` need it). Not
  WSL: WSL2 needs Hyper-V, which experiment 2 turns off.

## 0. Setup

```powershell
mkdir C:\book4-windows
git clone https://github.com/n1c0la84/book4-edge-linux C:\src\book4-edge-linux
cd C:\src\book4-edge-linux
```

Record the starting configuration (save, don't commit raw):

```powershell
$o = "C:\book4-windows"
bcdedit /enum '{current}' > $o\bcdedit-start.txt
Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard |
  Format-List * > $o\deviceguard-start.txt
(Get-CimInstance Win32_ComputerSystem).HypervisorPresent > $o\hypervisor-start.txt
Get-PnpDevice -PresentOnly | Where-Object InstanceId -like 'ACPI\QCOM*' |
  Sort-Object InstanceId | Format-Table -AutoSize Status,Class,FriendlyName,InstanceId > $o\qcom-devices.txt
driverquery /v /fo csv > $o\drivers.csv
```

## 1. Baseline (Hyper-V on, as shipped)

One standby test, then:

```powershell
powercfg /sleepstudy /output C:\book4-windows\sleepstudy-baseline.html
```

From the last session note: duration, **HW Drips %**, SW Drips %, top
offenders. Expected ~98 % HW. If it isn't, stop and investigate why first:
the comparison below needs a working baseline.

## 2. Test whether Windows needs Hyper-V for DRIPS

Disabling Hyper-V tests whether Windows still reaches DRIPS without it. The
`HypervisorPresent` check below confirms the Microsoft hypervisor is absent;
it does not by itself establish that Gunyah owns EL2 or that Windows uses the
same PSCI path as Linux.

1. BitLocker: have the recovery key (account.microsoft.com, Devices,
   Recovery keys) **or** suspend protection for the reboots:
   `manage-bde -protectors -disable C: -RebootCount 3`
2. Windows Security, Device security, Core isolation: Memory integrity off
   (user clicks; reboot it asks for can wait for step 3).
3. `bcdedit /set hypervisorlaunchtype off`, reboot.
4. Verify: `(Get-CimInstance Win32_ComputerSystem).HypervisorPresent` is
   `False`, and Win32_DeviceGuard `VirtualizationBasedSecurityStatus` is 0.
   If Windows does not boot or refuses: that is a result too; undo below.
5. One standby test; `powercfg /sleepstudy /output C:\book4-windows\sleepstudy-nohv.html`.
6. Undo: `bcdedit /set hypervisorlaunchtype auto`, Memory integrity on,
   reboot, verify `HypervisorPresent` is `True` again.

| HW DRIPS without Hyper-V | Meaning | Next |
|---|---|---|
| still ~98 % | Hyper-V is not required in this Windows configuration; another boot or standby difference remains | experiment 3A |
| ~0 % | disabling Hyper-V removed a condition needed for DRIPS; the specific condition is not yet identified | experiment 3B |

## 3A. Driver bisection (if DRIPS survives without Hyper-V)

Disable one device (or one driver's devices) at a time, standby test,
re-enable. Use the device list from step 0. Order, most suspicious first
(blocks Linux drives partly or not at all):

1. Display/GPU (`qcdx8380`, Adreno, display RSC user): disabling falls
   back to Microsoft Basic Display; the screen stays usable.
2. Video encode/decode, camera (`qccamera*`, CAMSS, ISP), webcam sensor.
3. NPU / compute DSP (`qcnspmcdm*`, CDSP subsystem).
4. Secure Processor (`QCOM0C8D`, `qcsubsys_ext_spss8380`).
5. Crypto engine, sensors (`SEN2`, SAR sensors `SAMM0210`), fingerprint.
6. PCIe Wi-Fi, Bluetooth.
7. Audio (ADSP): last, and only if battery/charging is known not to depend
   on it on Windows (on this SoC the ADSP also carries battery and USB-C).

```powershell
Disable-PnpDevice -InstanceId '<id>' -Confirm:$false   # test
Enable-PnpDevice  -InstanceId '<id>' -Confirm:$false   # undo
```

If removing one device drops HW DRIPS to ~0 and re-enabling it restores DRIPS,
trace that driver's standby actions (section 4). This establishes a Windows
dependency, but still needs comparison with Linux to identify the missing
action.

## 3B. DRIPS fails with Hyper-V disabled

Restore Hyper-V and repeat the baseline to confirm the change is reversible.
Then determine which boot or power-management behavior changed. Useful leads:

- Trace standby entry with Hyper-V on (section 4) and look for hypervisor
  events around DRIPS.
- On Linux: `~/src/hyperv-re` has `hvaa64.exe`, `securekernel.exe` and
  PDBs; look for SMC calls to TrustZone other than PSCI that Hyper-V makes
  at launch or before CPU_SUSPEND (vendor SiP/OEM service calls), which
  Linux at EL2 never makes.

## 4. Trace a standby entry

```powershell
wpr -profiles | Select-String -Pattern Power   # find the built-in power profile name
wpr -start Power -filemode
# lid closed ~3 minutes, open, log in
wpr -stop C:\book4-windows\standby.etl
tracerpt C:\book4-windows\standby.etl -o C:\book4-windows\standby.xml -of XML -summary C:\book4-windows\standby-summary.txt
logman query providers | Select-String -Pattern 'pep|qc|qualcomm|power' > C:\book4-windows\providers.txt
```

Look for: PEP device/component idle transitions in the last seconds before
DRIPS, which devices were last to go idle, and anything from Qualcomm
providers. Summarize in Results; keep the ETL out of the repo.

## Results

(Nothing yet. Add one dated entry per experiment: configuration
(hypervisor present yes/no, VBS on/off, devices disabled), standby
duration, HW/SW DRIPS %, top offenders. No personal data.)
