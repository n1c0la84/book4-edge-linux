# System updates (`dnf update`)

Checked on 1 October 2026 against 963 pending Fedora 45 updates.

**Status (1 October 2026):**

- GRUB packages updated first (2.12-76 to 2.12-81) through
  `install/guard-grub.sh`; the guard restored `grub.cfg` and the machine
  booted normally.
- Then the rest of the system, holding back the kernel and firmware:
  `sudo dnf update --exclude='kernel*' --exclude='*firmware*'` (1265 package
  changes, on the Anatase kernel). `grub.cfg` still had `cutmem`; the Wi-Fi
  firmware, audio topology alias and UCM profile were untouched. The reboot
  after it is **not yet verified**.
- Not yet experienced: a Fedora **kernel** update and a **firmware** package
  update; "Safe by design" below is still analysis for those.

Excluding the Fedora kernel costs little while the Anatase kernel is the
default: it is only the fallback. To keep it excluded permanently, add
`excludepkgs=kernel*` to `[main]` in `/etc/dnf/dnf.conf`.

## The one real danger: GRUB updates

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

## Safe by design

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

## Procedure

1. Charger connected.
2. `bash install/guard-grub.sh` once (installs the guard and tests it on a
   GRUB-only upgrade).
3. `sudo dnf update`
4. `sudo grep -c cutmem /boot/efi/EFI/fedora/grub.cfg` must be >= 1.
5. Reboot into the default entry (still the pinned kernel).
