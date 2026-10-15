# Linux at EL2 (no Qualcomm hypervisor)

**Status (15 October 2026): works, experimental.** Arch boots at EL2 with
KVM, from a USB stick that loads [slbounce](https://github.com/TravMurav/slbounce)
before the normal GRUB. No audio (the DSPs cannot start), no RTC and no
UEFI variables. Nothing on the internal disk's ESP or in the firmware's
boot entries changes; without the stick the machine boots as before.

## Why

On ARM, an OS kernel runs at EL1 and a hypervisor at EL2. The firmware
starts Qualcomm's hypervisor (Gunyah/QHEE) at EL2 on every boot, and Linux
runs under it: it emulates the "SBSA" watchdog Linux sees, owns the PCIe
SMMU and starts the DSPs. Windows replaces it with Hyper-V through
Microsoft's Secure Launch (`tcblaunch.exe`, signed, accepted by the
firmware); slbounce uses the same mechanism to hand EL2 to Linux.

The reason to try: on 14 October the machine reset by itself at **47 h
59 min of wall-clock uptime** (8.4 h awake, the rest suspended), with
nothing in the journal and no pstore. No earlier Arch boot had lasted that
long (the longest: 45.5, 45.1 and 44.5 h). A time-based reset in firmware
that keeps counting during sleep (hypervisor, EC or AOP) fits; Windows
never runs Qualcomm's hypervisor, so it would never see one there. One
event proves nothing: the test is a boot at EL2 kept up past 48 h.

What Windows does instead, from its driver store: `HalExtQCWdogTimer.dll`
(Qualcomm HAL extension, `ACPI\QCOM0C04`, CSRT group `QCOM 0x100B` at
`0x17410000`) drives the APSS watchdog only when the hypervisor vendor is
`MsHyperV`: enable/bite/bark registers as in Linux's `qcom_wdt` (reset
`+0x4`, enable `+0x8`, bark `+0x10`, bite `+0x14`). Windows' GTDT lists no
SBSA watchdog. Linux at EL1 keeps that node `status = "reserved"`; the EL2
overlay sets it `okay` and disables the Gunyah-emulated SBSA one.

## Secure-Launch test (15 October)

`sltest.efi` from slbounce, from the stick's UEFI shell:
`Available: 0x0`, `Auth: 0x0`, `Launch:`, then a green band across the top
of the screen and a hang. That band is drawn by slbounce's trampoline
after `hvc 0x1` returned in EL2 (`src/trans.s`, `draw_on_screen` then
`halt`, on purpose): **EL2 reached**. Same result with tcblaunch
10.0.26100.9616 (this machine's Windows, October 2026) and 10.0.26100.4351
(Microsoft symbol server, reported good on other X1E laptops); the "newer
builds lost the error handling" warning in slbounce's README does not
apply to 9616 here.

## How to boot it

1. Build slbounce natively on Arch (`make CROSS_COMPILE=`).
2. [`install/el2/make-usb.sh /dev/sdX`](../install/el2/make-usb.sh): UEFI
   Shell (pinned release, hash checked), `slbounce.efi`, `sltest.efi`,
   `tcblaunch.exe` from the read-only mounted Windows (never committed) and
   [`startup-el2.nsh`](../install/el2/startup-el2.nsh) as `startup.nsh`;
   verifies every file (the first, cheap stick dropped off the USB-C bus
   mid-write once).
3. [`install/el2/el2-dtb.sh`](../install/el2/el2-dtb.sh): the default DTB
   plus [`dts/src/x1-el2-book4.dtso`](../dts/src/x1-el2-book4.dtso) (upstream
   `x1-el2.dtso` without the ADSP/CDSP `iommus`, which cause an apps-SMMU
   fault storm on X1E laptops) as `/boot/dtb-test/<name>-el2.dtb`, and the
   GRUB test entry "el2" (`id_aa64mmfr0.ecv=1`: per the HP OmniBook notes the
   firmware resets on `CNTPOFF_EL2` access). The DTB must have `__symbols__`.
4. Power off, F10, the stick. The shell finds the stick and the internal
   ESP (scans `fs0`-`fs63`: UFS shows up as ~90 block devices), waits for a
   key (`q` stops), loads slbounce and starts `\EFI\fedora\grubaa64.efi`.
   Pick "... - test: el2".

slbounce only switches when the DTB GRUB passed has the GPU zap shader
disabled (`sl_is_allowed_by_fdt()` in `src/bounce_main.c`); every other
entry, and Windows (no DTB), boots exactly as without it. Secure Boot must
stay off (it is anyway: `cutmem` is refused under lockdown).

## What works at EL2 (first boot, 15 October)

`CPU: All CPU(s) started at EL2`, KVM up (`/dev/kvm`, nested-virt trap
handlers registered).

| | |
|---|---|
| Display, GPU | works (zap shader not needed at EL2) |
| Wi-Fi (PCIe 4, now behind Linux's PCIe SMMU) | works; one SMMU translation fault from `0004:01:00.0` at boot |
| Keyboard, touchpad, touchscreen, lid, power key | work |
| Battery, charger, USB-C ports (EC over I2C) | work |
| USB, fingerprint reader, camera nodes | present |
| APSS watchdog | `qcom_wdt`, Linux's own, inactive unless opened |
| **Audio, compute DSP** | **no**: `error -22 initializing firmware` (TrustZone refuses PAS without the hypervisor); Bluetooth/USB audio go through the ADSP too |
| **UEFI variables** | **none** (`qcom_qseecom` probe `-22`): `/sys/firmware/efi/efivars` is empty, `efibootmgr` cannot work |
| **RTC** | **none** (`RTC time: n/a`): `rtc-pm8xxx` needs the `RTCInfo` variable; the clock is right only once NTP syncs |
| Suspend | not tested yet |

Not tried: `cpuidle.off=1` (the HP OmniBook notes need it against input
lag). Starting the DSPs from EL2 needs qebspil (an EFI driver that boots
them before the switch, mentioned in slbounce's README) plus unmerged
kernel patches.

## On Arch: the /efi automount

Arch has no ESP line in `/etc/fstab`, so `systemd-gpt-auto-generator`
mounts the ESP at `/efi` on access and unmounts it after 120 s idle
(`efi.automount`; at boot `dbus-broker` triggers it). It is root-only
(`fmask=0177`) and nothing writes to it. `install/arch/test-entry.sh`
reads the ESP through such a mount if there is one.

## Next

- Keep one EL2 boot up past 48 h of wall-clock time, with normal lid-close
  suspends (after `tools/power/suspend-check.sh` passes at EL2). No reset:
  Qualcomm's hypervisor is the prime suspect; a reset anyway: look at the
  EC or AOP.

References: [slbounce](https://github.com/TravMurav/slbounce) and its
issues [#11](https://github.com/TravMurav/slbounce/issues/11) (tcblaunch
versions) and [#12](https://github.com/TravMurav/slbounce/issues/12)
(GRUB); [HP OmniBook X 14 notes](https://github.com/LukeMech/hp-omnibook-x14-fe0)
(X1E at EL2: DT changes, `id_aa64mmfr0.ecv=1`, what breaks).
