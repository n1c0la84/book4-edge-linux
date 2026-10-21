# Reproducing this machine

The order to set the Galaxy Book4 Edge 14" up from scratch, the way the
reference machine runs on 20 October 2026: **Arch Linux ARM + Omarchy as the
daily system, booted at EL2 with the sleep kernel (full s2idle deep sleep),
Fedora next to it** as the build host that owns `/boot` and GRUB. Each step
links the script that does it and the document that explains it.

Every script was run on the reference machine, but **the sequence as a whole
has never been run on an empty disk.** Read each script before running it.
All of them run as your user and call `sudo` themselves.

## What you need first

- **Windows, kept.** The DSP and GPU firmware and `tcblaunch.exe` (for EL2)
  come from it, and the firmware updates come through it.
  ([firmware.md](firmware.md))
- **Disk layout** (what the scripts assume): `sda1` ESP (shared with
  Windows: only add files, never delete), `sda3` Windows, `sda4` `/boot`
  (ext4, Fedora's), `sda5` btrfs with the subvolumes `root` and `home`
  (Fedora) and `arch` (Arch, with its own `/home`).
- A USB stick to boot Fedora's installer, and a charger.

## 1. Fedora: a machine that boots

1. Install Fedora (aarch64) with a hand-made GRUB config and device tree:
   [bootstrap.md](bootstrap.md). The load-bearing details are there (`cutmem`,
   a padded DTB, `cma=256M`, `mem_sleep_default=s2idle`).
2. The DSP/GPU firmware from Windows and the Wi-Fi firmware:
   [firmware.md](firmware.md).
3. The base layer and the fallback kernel's drivers:
   `bash install/install-fedora.sh [BLUETOOTH_ADDRESS]` (boot hook, keyboard,
   audio profile, Bluetooth address, Anatase's drivers through DKMS). With
   the stock Fedora kernel that is already a working laptop (battery, USB-C,
   charging, audio), minus the keyboard backlight, EFI variables and the
   clock. `install/update-boot-hook.sh` and `install/update-audio.sh`
   reinstall those pieces from the repo later.
4. The GRUB guard before any `dnf update`: `bash install/guard-grub.sh`
   ([updates.md](updates.md)).

## 2. The kernel (on Fedora)

5. Build `7.2.7-book4` from
   [`book4/7.2`](https://github.com/n1c0la84/linux-book4-edge/tree/book4/7.2)
   in `~/src/patchwork`, then `bash install/install-anatase-kernel.sh`
   ([kernel.md](kernel.md)). This is Fedora's default kernel, the EL1 kernel
   and the one every other build starts from.
6. Optional: the camera device tree, `bash install/camera-dtb.sh`
   ([camera.md](camera.md)); the fingerprint reader,
   `bash install/fingerprint-libfprint.sh` then `bash install/fingerprint.sh`.

## 3. Arch Linux ARM next to it

From Fedora ([arch.md](arch.md) has the details and the lessons):

7. `bash install/arch/stage1-base.sh`: the `arch` subvolume, base system,
   modules and firmware, initramfs into `/boot`, GRUB entry.
8. `bash install/arch/stage2-desktop.sh`: Hyprland, PipeWire with our UCM
   profile, Bluetooth address.
9. `bash install/arch/sync-audio.sh`, and `bash install/arch/sync-fingerprint.sh`
   if step 6 was done.

Then boot Arch, and on Arch:

10. Omarchy: `stage3-omarchy-build.sh`, `stage3-omarchy-install.sh`,
    `stage3-omarchy-user.sh`, then `stage3-yay.sh` (held packages) and
    optionally `stage3-chrome.sh`, all in `install/arch/`
    ([arch.md](arch.md), [omarchy.md](omarchy.md)). `stage3-omarchy-install.sh`
    also masks `linux-modules-cleanup.service`, which must stay masked: it
    deletes the module trees of every kernel but the running one.
11. Arch as GRUB's default, plus the suspend defaults (`pcie_port_pm=force`,
    no USB wakeup): `bash install/arch/boot-defaults.sh`. Then the low-battery
    policy (a last warning at 5 %, a clean power-off at 3 %):
    `bash install/arch/battery-policy.sh`. And a log of every sleep (minutes,
    mAh, watts, deep-sleep residency): `bash install/arch/sleep-log.sh`.
    Optional: the Copilot key as Super (keyd): `bash install/arch/copilot-key.sh`.

From here, Fedora's container is used from Arch for kernel builds
(`install/arch/fedora-shell.sh`); Fedora itself does not need to be booted.

## 4. Deep sleep: the sleep kernel at EL2

On Arch, booted normally (EL1, kernel `7.2.7-book4`):

12. The sleep kernel `7.2.7-book4s` (7.2.7 + `tools/kernel/sleep-backport/`)
    and its modules: `bash tools/kernel/build-sleep-kernel.sh` (an hour or two
    in Fedora's container).
13. The EL2 boot programs, from pinned commits:
    `bash install/el2/build-efi.sh` (qebspil with the AOSS patch, slbounce).
14. Onto the ESP, with a firmware boot entry "Book4 EL2 (slbounce)":
    `bash install/arch/mount-ro.sh` (for Windows' `tcblaunch.exe`), then
    `bash install/el2/esp-install.sh` ([el2.md](el2.md)).
15. Everything else, in one script: `bash install/el2/sleep-setup.sh`. It
    creates the GRUB entry "el2-sleep", installs `book4-el2-sleep.service`
    (`el1tmr`, the UFS hold, releasing the boot votes at every EL2 boot),
    blacklists `qcom_adsp_pwr_lmts`, and makes EL2 the default boot (firmware
    boot order and GRUB default together; this part needs an EL1 boot).
16. Reboot. Check with `bash tools/power/el2-drain-test.sh` on battery:
    `aosd`/`cxsd`/`ddr` should be near 99 % ([power.md](power.md)).

**At EL2** EFI variables, the RTC and `efibootmgr` work since 21 October
(sleep-backport 0027/0028 and the `qcom,shm-bridge-vmid` property in the EL2
overlay). The normal entries stay in the GRUB menu, and F10 at power-on
still picks the firmware's other entries.

## Undo and recovery

- EL2 default off: `bash install/el2/sleep-setup.sh undo` (on EL1), or F10 →
  the Fedora entry → an EL1 entry.
- A broken Arch: Fedora boots on its own, and `tools/backup/snapshot-arch.sh`
  snapshots taken before updates can be restored from it.
- Old test entries and kernels: `bash install/arch/boot-cleanup.sh`.
- A rescue stick: `install/arch/rescue-usb.sh` (built, never boot-tested).
