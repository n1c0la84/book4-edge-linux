# Arch Linux ARM next to Fedora (toward Omarchy)

Status on 2 October 2026, 14" NP940XMA. This is the working log for the Arch
side; [omarchy.md](omarchy.md) has the background and the two routes.

## Layout

- Same btrfs filesystem as Fedora (`sda5`), subvolume **`arch`** next to
  Fedora's `root`; separate `/home` inside each subvolume. No repartitioning.
- **Shared kernel**: Arch boots the Anatase kernel `7.2.7-book4` built and
  installed on Fedora (`/boot` is Fedora's ext4 partition), with the same
  default DTB (the camera DTB, see [camera.md](camera.md)).
- GRUB entry "Arch Linux (7.2.7-book4)" comes from the Fedora boot hook:
  `/etc/book4/second-os` on **Fedora** holds `arch Arch Linux`; the hook adds
  the entry when `/boot/initramfs-<kver>-arch.img` exists, with
  `rootflags=subvol=arch`.
- Arch's own kernel package (`linux-aarch64`) is removed. Kernel modules are a
  copy of Fedora's `/usr/lib/modules/7.2.7-book4`.
- Our firmware (Samsung DSP, GPU SQE, ath12k c5 set, topology alias) is in
  `/usr/lib/firmware/updates/` in Arch: searched first, never touched by pacman.

## How it was built (all from Fedora, in a container)

| Script | What |
|---|---|
| [`install/arch/stage1-base.sh`](../install/arch/stage1-base.sh) | subvolume, Arch Linux ARM tarball (signature checked by hand first), modules + firmware, locale/timezone, keyboard udev rule, mkinitcpio (UFS modules, no autodetect), pacman keys, fast mirrors (`dk`, `de4`), update, base packages, user with sudo, initramfs into Fedora's `/boot`, GRUB entry |
| [`install/arch/stage2-desktop.sh`](../install/arch/stage2-desktop.sh) | keyboard layout, Hyprland + Quickshell + uwsm + SDDM, PipeWire + our UCM profile, Bluetooth address service, `pipewire-libcamera`, Chromium, fonts, tray tools, starter `~/.config/hypr/hyprland.lua` |
| [`install/arch/collect-logs.sh`](../install/arch/collect-logs.sh) | from Fedora: the last Arch boot's journal, SDDM and Hyprland logs to `~/arch-logs.txt` |

Lessons, in the order they bit:

1. GNU tar on Fedora drops `security.capability` xattrs from the Arch
   tarball; stage 1 reinstalls every package once to restore them (or use
   `bsdtar`).
2. In `systemd-nspawn`, Arch's `/etc/resolv.conf` is a symlink into `/run`:
   use `--resolv-conf=replace-uplink`.
3. `mirror.archlinuxarm.org` (geo-redirect) stalled on large files; `dk.` and
   `de4.mirror.archlinuxarm.org` were fast from here.
4. **Hyprland 0.56 uses a Lua config** (`/usr/share/hypr/hyprland.lua`,
   `~/.config/hypr/hyprland.lua`); there is no `hyprland.conf` example any more.
   Omarchy 4 is Lua too.
5. **`linux-firmware-qcom` is not part of Arch's default firmware set.**
   Without it `qcom/gen70500_gmu.bin` is missing, the Adreno does not come up
   (`MESA: get-param failed`, `failed to create dri2 screen`) and Hyprland
   aborts right after login, dropping back to SDDM.

## What works (verified)

- Boot to a console, Wi-Fi via NetworkManager, internet.
- SDDM greeter.

## Where it stands / next steps

1. **Verify the desktop** after `linux-firmware-qcom` (installed 2 October,
   not yet booted): log in via SDDM to Hyprland; check scale, Italian
   keyboard, touchpad, sound (speakers, mics), Bluetooth, camera
   (`cam -l`, PipeWire "Built-in Front Camera"), keyboard backlight and
   hotkeys, suspend, battery in the tray.
2. **Omarchy's desktop from source** (step 2 in [omarchy.md](omarchy.md)):
   `omacom/omarchy`, branch `quattro`. Do **not** install the `omarchy`
   package: it depends on Limine, `limine-mkinitcpio-hook`,
   `limine-snapper-sync` and snapper, which would write boot entries to the
   ESP shared with Windows and Fedora's GRUB. Omarchy's aarch64 repository
   (`pkgs.omarchy.org/stable/aarch64`) has only 39 packages and no
   `omarchy`, `omarchy-settings` or `quickshell`; Arch Linux ARM has
   `hyprland` 0.56.2 and `quickshell` 0.3.1. omarchy-shell runs from
   `$OMARCHY_PATH/shell` under Quickshell, launched by
   `omarchy-launch-shell` from Hyprland autostart.
3. Compare with `bprendie/omarchy-snapdragon` (Omarchy 4.0.3 on Arch Linux ARM
   userspace with an Ubuntu kernel) for the aarch64 packaging they had to do.
4. Kernel updates: a new Anatase build on Fedora must also be copied into
   Arch (`/usr/lib/modules/<kver>`), and Arch's initramfs rebuilt
   (`mkinitcpio -k <kver> -g ...`, copied to `/boot/initramfs-<kver>-arch.img`).
   Not scripted yet.

## Rules that still apply in Arch

- Never write to or delete from the ESP (`/boot/efi`, shared with Windows);
  no bootloader packages (Limine, systemd-boot, grub installs) in Arch.
- `/boot` is Fedora's partition: Arch must not mount it as its own `/boot`
  for kernel packages.
- Never `modprobe -r ath12k` or rescan PCI. Keep `cutmem` and `cma=256M`
  (they live in Fedora's GRUB config).
