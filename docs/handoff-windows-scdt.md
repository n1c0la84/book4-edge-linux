# Windows handoff: does Windows ever call SCDT ("set cable detect")?

**Done, 8 October: no.** `SCDT` did not run for an awake plug-in or for a
plug-in in Modern Standby; fix B is dead. Firmware debug output is visible
in DebugView (SafiDrv prints it with `DbgPrintEx`). Details:
[power.md](power.md#charging-stalls-after-a-plug-in-while-awake-6-7-october-2026).

Written 7 October 2026 on Arch, for a Claude Code session **in Windows** on
the same machine (Samsung Galaxy Book4 Edge 14", NP940XMA). Read this, then
[power.md](power.md#charging-stalls-after-a-plug-in-while-awake-6-7-october-2026)
for the background. Only needed if the 0004 test shows charging still stuck
at ~1-2 W after an awake plug-in (see the end of this file).

## The question

On Linux, a charger plugged in while the laptop is awake gets a 20 V
contract but the battery charges at ~1 W; plugged in during sleep it charges
fine. One idea ("fix B"): Windows tells the EC about the charger and Linux
does not. In the firmware (DSDT) the only path to the EC's "CableDetect"
command (EC command `0x0d`, handled by Samsung's `EC2.sys`) is the ACPI
method **`\_SB.ECTC.SCDT`**, and nothing in the ACPI tables calls it. No
Windows driver, Samsung program or Samsung Store app contains the string
`SCDT` or `\_SB.ECTC` (searched from Linux, read-only). So either some
Windows component evaluates it in a way that search missed, or it is unused.

**Goal: find out whether `SCDT` runs when a charger is plugged in under
Windows, and with what value.** If it does, Linux can send EC command 0x0d
with that value after a contract (then a samsung-emuec patch). If it never
runs, fix B is dead: record that and stop.

## What the firmware does (DSDT)

The full ACPI dump is in Fedora's `~/src/acpi/` (all tables, there are no
SSDTs; `dsdt.dsl` decompiled) and the raw DSDT in Windows at
`C:\Users\nicol\Downloads\acpidump\dsdt.dat`. Line numbers refer to
`dsdt.dsl`:

- ~58836: `OperationRegion (MCU1, 0xA0, Zero, 0x10)` in `\_SB.ECTC`, fields
  `BTPT` (BTPThreshold, EC cmd 0x06), **`CBDT` (CableDetect, EC cmd 0x0d)**,
  `RESP` (Modern Standby phase), `PSRC` (read in `_Q51`/`_Q52`, charger
  events). Region space 0xA0 is served by Samsung's `EC2.sys`.
- ~58866: `Method (SCDT, 1)` { `ADBG ("SCDT:" + hex(Arg0))`; `CBDT = Arg0` }.
- ~61309: `Method (ADBG, 1)` { `\_SB.SAFI.PRNT (Arg0)` }.
- ~59244: `Device (SAFI)`, `_HID "SAM0701"`, "Samsung Firmware Interface".
- ~59300: `Method (PRNT, 1)` { if `\_SB.SAFI.AVBL == 1`: `AAAA = Arg0`
  (field in region `ECM2`, space 0x9F), `Notify (\_SB.SAFI, 0x89)` }.

So every firmware debug message, including `SCDT:<value>`, goes to the
**SAM0701 driver** as a string plus a notification, and only if that driver
has set `AVBL` (registered). Standard kernel debug output (DebugView) will
not show it. Also visible in the DSDT: region `EMOP` (space 0x9C: `CHGS`,
`CHTY`, `CCST`, ...: USB-C/charger state) and `BMOP` (0x9E: battery
manager), served by other drivers; a caller of `SCDT` would likely read
`CHTY`/`CHGS` first.

## Rules on this machine

- **The EFI system partition is shared** with Linux (Fedora's GRUB, our
  `\EFI\fedora\grub.cfg`, `\EFI\book4\`): do not run `bcdedit`, `bcdboot`,
  disk or boot repair tools, and do not touch the ESP.
- Read-only investigation: no driver installs or removals, no registry
  edits beyond what a trace needs, no EC writes. ETW traces are fine.
- Ask before anything public (issues, uploads). No personal data (MAC, IP,
  SSID, serials) in the repo.

## Steps

1. Get this repo (`git clone https://github.com/n1c0la84/book4-edge-linux`,
   or pull an existing clone). Admin PowerShell for the rest.
2. Find the SAM0701 driver:
   `Get-PnpDevice | Where-Object InstanceId -match 'SAM0701'`, then
   `Get-PnpDeviceProperty -InstanceId <id> -KeyName DEVPKEY_Device_Service,DEVPKEY_Device_DriverInfPath,DEVPKEY_Device_DriverVersion`,
   the service's `ImagePath` under
   `HKLM:\SYSTEM\CurrentControlSet\Services\<service>` and its `Parameters`.
   Note also which driver owns `EC2.sys` and the ECTC device.
3. Find how it records the firmware strings: its event-tracing providers
   (`logman query providers | findstr /i "samsung safi"`, the driver's
   manifest/`.inf`), an event log (Event Viewer, Applications and Services
   Logs), a log file (strings in the `.sys` such as paths, `.log`, `%s`), or
   registry debug switches in `Parameters`. If the driver exposes nothing,
   a trace of `Microsoft-Windows-Kernel-Acpi` may still show the `Notify
   (SAFI, 0x89)` events (one per firmware message, without the text).
4. Capture: start the trace (`logman create trace scdt -p <provider> 0xffffffffffffffff 0xff -o C:\scdt\scdt.etl -ets`,
   one `-p` per provider, or `wpr` with a custom profile), unplug the
   charger, wait 10 s, plug it in, wait 60 s, stop (`logman stop scdt -ets`),
   convert (`tracerpt C:\scdt\scdt.etl -o C:\scdt\scdt.xml -of XML`) and
   search for `SCDT`, `CBDT`, `PSRC`, `0x89`. Repeat with the lid closed
   during the plug-in if possible (that is the path that works on Linux).
5. Record the outcome in [power.md](power.md) under "Fix B" (driver name,
   how its log was read, whether `SCDT` appears, the value and the moment
   relative to the plug-in), commit and push from Windows. Put raw captures
   in `C:\scdt\` (not the repo): the Linux side can read them from the
   read-only mounted partition.

## Context for the Linux side

- Patches 0001-0003 (PD retry, quiesce across sleep, wake on plug-in) are
  in use on Fedora and Arch; experimental 0004 (grace period before the
  first PD request, `pd_grace_ms`) is installed on Arch since 7 October.
  0004 removed the failed first request but a 5 V step remains for ~3 s.
- Test that decides whether this handoff is needed:
  `bash tools/power/charge-test.sh awake-0004 20` on Arch, battery below
  ~80 %: about 20 W or more into the battery = fixed (skip this handoff),
  ~1-2 W = not fixed (do this handoff).
- Workaround meanwhile: plug the charger in with the lid closed.
