# Updating the system

Arch is the daily system (since 16 October) and gets updated often; Fedora
only matters as the build host that owns `/boot` and GRUB, but a GRUB
package update there is still the one way to break booting. Kernels are
ours and never come from a package. How the machine was set up:
[install.md](install.md).

## Arch (daily)

The tested path, about weekly:

1. Charger connected.
2. `bash tools/backup/snapshot-arch.sh pre-update`: a read-only btrfs
   snapshot of the `arch` subvolume (includes `/home`); the rollback is in the
   script's header.
3. `sudo pacman -Syu`, then `yay -Sua`, then `mise up`. (`omarchy update`
   should do the same, see [arch.md](arch.md) "Updating"; not yet run here.)
4. Reboot only if something low-level changed (systemd, Mesa, firmware).
   `omarchy-update-restart` always offers a kernel reboot (our kernel is not
   a package): answer no.

**Held packages** (`IgnorePkg` in `/etc/pacman.conf`, set by
`install/arch/stage3-yay.sh`): `omarchy`, `omarchy-settings`,
`omarchy-keyring`, `mise-bin`, `google-chrome` (installed by hand: no
configured repository has them, so `yay` would try to replace them) and
`mkinitcpio` (held since 13 October; our kernel has no package or preset,
so its hooks never run anyway). They are updated by hand: Omarchy with a
newer pin in `stage3-omarchy-build.sh` after reviewing its migrations and the
`NoExtract` list ([arch.md](arch.md)); the others with `pacman -U` from
Omarchy's aarch64 repository.

**Never** unmask `linux-modules-cleanup.service` (it deletes the module trees
of every kernel but the running one; [kernel.md](kernel.md), 19 October), never
run `omarchy-reinstall-configs`, and never let Omarchy's
`install/post-install/pacman.sh` run (it writes x86 mirrors).

## Kernels

Two kernels, both ours: `7.2.7-book4` (EL1, Fedora's default, the build base)
and `7.2.7-book4s`, the sleep kernel booted at EL2 every day. A kernel update
is a rebuild, done on Arch through Fedora's container:

- The sleep kernel, from any boot: `bash tools/kernel/build-sleep-kernel.sh`,
  then `bash install/el2/sleep-setup.sh` (re-creates the EL2 entry from the
  new DTB and keeps the defaults). When the sleep kernel itself is running,
  its new modules are staged in `/var/lib/book4/staged` and swapped in at
  the next boot (`book4-modules-swap.service`, before anything loads modules
  from disk; the previous set stays as `<release>.old`), so reboot when it
  suits you. Patches added at the end of the set build incrementally.
- Only its out-of-tree modules: `bash tools/kernel/build-sleep-modules.sh`.
- The base kernel: [kernel.md](kernel.md), then
  `bash install/arch/sync-kernel.sh` for Arch.
- Moving to 7.3: planned once Anatase has a 7.3 tree; most of
  `tools/kernel/sleep-backport/` is already in 7.3.

**DSP firmware:** qebspil loads its own copy from the ESP
(`\firmware\qcom\x1e80100\SAMSUNG\galaxy-book4-edge\`). After changing the
firmware in `/usr/lib/firmware/updates/`, run `bash install/el2/esp-install.sh`
again (EL1) so the two stay the same.

## Fedora (`dnf update`)

Checked on 1 October 2026 against 963 pending Fedora 45 updates.

**Status (1 October 2026):**

- GRUB packages updated first (2.12-76 to 2.12-81) through
  `install/guard-grub.sh`; the guard restored `grub.cfg` and the machine
  booted normally.
- Then the rest of the system, holding back the kernel and firmware:
  `sudo dnf update --exclude='kernel*' --exclude='*firmware*'` (1265 package
  changes, on the Anatase kernel). `grub.cfg` still had `cutmem`; the Wi-Fi
  firmware, audio topology alias and UCM profile were untouched. After a
  reboot everything worked (display, GPU, Wi-Fi, Bluetooth, audio, battery,
  keyboard backlight, EFI variables, RTC).
- Not yet experienced: a Fedora **kernel** update and a **firmware** package
  update; "Safe by design" below is still analysis for those.

Excluding the Fedora kernel costs little while the Anatase kernel is the
default: it is only the fallback. To keep it excluded permanently, add
`excludepkgs=kernel*` to `[main]` in `/etc/dnf/dnf.conf`.

### The one real danger: GRUB updates

`/boot/efi/EFI/fedora/grub.cfg` is our static configuration (`cutmem`,
`devicetree`, explicit kernel paths). The `grub2-efi-aa64` package marks it as a
ghost file, but its `%posttrans` scriptlet runs

    cp -d --preserve=all /usr/lib/efi/grub2/<version>/EFI/fedora/* /boot/efi/EFI/fedora

which replaces it with Fedora's stub. The stub chains to `/boot/grub2/grub.cfg`
(BLS entries without `cutmem` and with stale paths), so the next boot reboots
instantly or fails.

**Guard:** `install/guard-grub.sh` installs `libdnf5-plugin-actions` and a
post-transaction action (`userspace/dnf/`) that re-runs the boot hook after any
`grub2-efi-aa64` install/upgrade and checks that `cutmem` and `devicetree` are
back. Post-transaction actions run after all package scriptlets.

Whatever happens, before rebooting after an update:

    sudo grep -c cutmem /boot/efi/EFI/fedora/grub.cfg    # must be >= 1

If it is 0: `sudo /etc/kernel/install.d/99-book4-devicetree.install add $(uname -r)`.

`shim-aa64` would similarly overwrite `\EFI\BOOT\BOOTAA64.EFI` (the firmware's
default boot file). No shim update was pending when this was written; check
before updating (`dnf check-update shim-aa64`).

### Safe by design

- **Kernel updates.** The boot hook adds the new kernel as a "(other)" entry and
  keeps the pinned kernel (`/etc/book4/default-kernel`) as the default. DKMS
  builds both driver packages for the new kernel (its `kernel-devel` comes with
  it, since `kernel-devel` is installonly), dracut includes the DSP firmware,
  the hook copies the DTB. Try the new kernel from the menu, then pin it:
  `echo <version> | sudo tee /etc/book4/default-kernel` and re-run the hook.
- **Wi-Fi firmware.** Our c5-00302 files in `ath12k/WCN7850/hw2.0/` are
  uncompressed and not owned by any package; Fedora's `atheros-firmware` ships
  `.xz` files, and the kernel tries the uncompressed name first, so ours keep
  winning. A new `board-2.bin` could in principle change which board data is
  used; if Wi-Fi breaks after an update, see `docs/firmware.md`.
- **DSP firmware, audio topology alias, UCM profile, udev/modprobe/dracut
  snippets.** All are files no package owns, or live in `updates/` directories
  that take precedence.

### Procedure

1. Charger connected.
2. `bash install/guard-grub.sh` once (installs the guard and tests it on a
   GRUB-only upgrade).
3. `sudo dnf update`
4. `sudo grep -c cutmem /boot/efi/EFI/fedora/grub.cfg` must be >= 1.
5. Reboot into the default entry (still the pinned kernel).
