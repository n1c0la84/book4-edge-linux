# Updating the system

Arch Linux ARM + Omarchy 4.5 is the sole Linux installation on this machine
(Fedora was retired and deleted on 23 November 2026; see
[fedora-retired.md](fedora-retired.md)). Kernels and Book4 hardware support are
pacman packages in `[book4]` ([packages-online.md](packages-online.md)), and
pacman hooks keep `/boot` (Limine EL2 UKIs on `sda7`, fallback Arch GRUB on
`sda4`) and `/efi` (`sda1` EL2 chain) in sync automatically.

## Routine updates (Arch + Omarchy)

1. Connect the charger.
2. Run **`book4-update`** (`userspace/update/book4-update`, symlinked to
   `~/.local/bin/book4-update` by `install/arch/update.sh`):
   - Shows pending repo, AUR, `mise`, and `flea` updates (`book4-update --check`
     stops here without root).
   - Prunes the pacman cache and takes a read-only btrfs snapshot of the
     running root subvolume (`arch-45-pre-update-<stamp>`, keeping the newest 2)
     because `snapper` is not installed.
   - Delegates to **`omarchy-update`** (keyring refresh, PID 1 scope-shielded
     `pacman -Syu`, Omarchy migrations, shell update clear, service restarts,
     `mise`, AUR, and reboot prompt), automatically handling the case where
     `[omarchy]` shadows a newer `extra/hyprland` needed for `extra/hyprgraphics`.
   - Use `book4-update --direct` to bypass `omarchy-update` and run
     `pacman -Syu` / `yay` / `mise` directly.
3. **`90-book4-verify.sh` post-update hook** (`userspace/update/book4-post-update-check`,
   symlinked into `~/.config/omarchy/hooks/post-update.d/` by
   `install/arch/update.sh`): runs automatically at the end of every
   `omarchy-update` (even if launched from the Omarchy menu/bar) and verifies
   core Book4 packages, `libfprint-sdcp`, `linux-modules-cleanup.service`
   masked, `book4-el2 status`, `/boot/limine.conf` + UKIs, `Hyprland --verify-config`,
   and `.pacnew` files.
4. Review `.pacnew` files before rebooting. Reboot if the kernel, systemd,
   Hyprland, Mesa, PipeWire, or firmware updated.

**Rules to keep:**
- **Never** unmask `linux-modules-cleanup.service` while more than one kernel
  stays installed.
- **Never** run `omarchy-reinstall-configs`, `omarchy-refresh-limine`,
  `omarchy-setup-security-fingerprint` (replaces `libfprint-sdcp`), or
  Omarchy's x86 `install/post-install/pacman.sh`.
- Keep `folio` in `IgnorePkg` only while it is installed from Omarchy's `edge`
  channel ahead of `stable` (prevents AUR name clash).

## Updating Book4 packages

### From the online `[book4]` repository
Normal `omarchy-update` / `pacman -Syu` pulls new signed builds of
`linux-book4`, `book4-edge`, `book4-edge-boot`, `book4-edge-el2`, `fastrpc`,
`libssc-book4`, `iio-sensor-proxy-book4`, `book4-sensors`, and `libfprint-sdcp`
from GitHub Releases once published via `.github/workflows/packages.yml`.

### Locally on this laptop (`/var/lib/book4-repo`)
```sh
cd packages/<name> && makepkg -f
bash install/arch/book4-repo.sh add <name>
OMARCHY_ALLOW_DIRECT_PACMAN=1 sudo pacman -Syu
```

- **Kernel (`linux-book4`):** commit/push on `~/src/linux-book4` (branch
  `book4/7.3` of `n1c0la84/linux-book4-edge`), bump `pkgver`/`pkgrel` and
  `_commit` in `packages/linux-book4/PKGBUILD`, refresh
  `packages/linux-book4/config` if `.config` changed, then build and add as
  above. `91-book4-boot.hook` automatically builds the initramfs, EL1/EL2 DTBs,
  Limine EL2 UKI on `/boot` (`sda7`), and fallback Arch GRUB menu on `sda4`.
- **EL2 chain (`book4-edge-el2`) and DSP firmware (`book4-edge-firmware`):**
  `95-book4-el2.hook` automatically runs `book4-el2 update` to refresh
  `\EFI\book4-el2-arch\`, `\EFI\book4-el2-limine\`, and `qebspil`'s
  `\firmware\...` copy on `/efi` (`sda1`). Check with `book4-el2 status`.
- **Firmware (`book4-edge-firmware`):** stays local only (and optionally copied
  to the private LAN share via `install/arch/book4-private.sh publish`). Re-run
  `bash install/arch/firmware-stage.sh` before `makepkg -f` if `sha256sums.txt`
  changes.

## Verifying boot files after low-level updates

```sh
book4-el2 status                 # EL2 chains and DSP firmware on /efi current
ls -lh /boot/EFI/Linux/          # Limine EL2 UKIs present
cat /boot/limine.conf            # expected default kernel entry
```
