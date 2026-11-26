# Fedora retired and deleted (19–23 November 2026)

Fedora is no longer installed: the kernel is built and packaged natively on
Arch (`packages/linux-book4`), Limine on `sda7` (`BOOK4ESP`) is the default
bootloader with Arch GRUB on `sda4` as fallback, and Fedora's data was archived
into `~/fedora-archive/` (`install/arch/fedora-retire.sh archive`). **Fedora
was deleted on 23 November 2026** (`install/arch/fedora-delete.sh --yes`:
subvolumes `root`, `home`, and pre-4.5 `arch` removed, plus Fedora's kernel and
rescue files on `sda4`). `\EFI\fedora\` stays on `sda1` (hard rule) as a
fallback firmware entry.

## The archive

`~/fedora-archive/` in Arch (MANIFEST.txt lists everything):

- `home/`: Fedora's home without the kernel trees, build outputs, `.cache`
  and Chrome's profile (`BOOK4_FEDORA_CHROME=1` to include it), as reflinked
  copies: no extra space until Fedora is deleted.
- `kernel/`: the shallow 7.2 trees `patchwork` and `patchwork-sleep` as whole
  `.git` copies, with their uncommitted changes (`*.dirty.patch`, 69 files in
  `patchwork-sleep`: the 7.2.7-book4s fallback kernel's source state),
  untracked files and `.config`; `linux-73`'s branches are fetched into
  `~/src/linux-book4` as `refs/fedora/linux-73/*`.

## Scripts that used Fedora

| Script | Status |
|---|---|
| `tools/power/{gdsc-drips,gic-pending,icc-hold,rscc-dump,spss-check,timer-check,vreg-off}/build.sh` | **ported**: `tools/power/build-module.sh`, against linux-book4-headers (all seven built on 7.3.4-book4) |
| `tools/power/rpmh-read/build.sh`, `tools/kernel/build-pdc-kernel.sh` | obsolete: the 7.2 PDC test kernel |
| `tools/power/psci-probe/` | needs a prepared kernel tree argument; use `~/src/linux-book4` |
| `tools/kernel/build-73-kernel.sh`, `build-sleep-kernel.sh`, `build-sleep-modules.sh`, `update-sleep-emuec.sh`, `update-sleep-galaxybook-ec.sh`, `install/update-galaxybook-ec-module.sh`, `install/install-anatase-kernel.sh`, `tools/power/build-ufs-patch.sh` | replaced by `packages/linux-book4` (makepkg) and `tools/kernel/install-book4-kernel.sh` |
| `install/kernel-branch.sh`, `tools/kernel/check-branch.sh`, `tools/kernel/show-file.sh`, `tools/kernel/push-fork-readme.sh` | replaced by git in `~/src/linux-book4` (branch book4/7.3 on the fork) |
| `tools/kernel/audio-bisect-73.sh`, `fp-dts-info.sh`, `fp-test-dtb.sh`, `woofer-names-dtb.sh`, `merge-dts-patches.sh`, `tools/experiments/cleanup-power-tests.sh`, `tools/experiments/grub-cleanup.sh` | finished experiments (7.2 era) |
| `userspace/boot/99-book4-devicetree.install`, `userspace/dnf/book4-regen-grub`, `install/update-boot-hook.sh`, `install/guard-grub.sh` | Fedora's boot hook; replaced by `book4-boot` (userspace/boot/arch) |
| `install/camera-dtb.sh`, `install/speakers-dtb.sh`, `install/speakers-default.sh`, `install/gpio44-test.sh` | 7.2 DTB variants through Fedora's hook; on Arch: `install/arch/test-entry.sh add NAME dtb=/PATH` |
| `install/arch/boot-defaults.sh`, `power-defaults.sh`, `boot-cleanup.sh`, `sync-kernel.sh`, `stage1-base.sh`, `rescue-usb.sh` | history of the Fedora-hosted setup; not to be rerun |
| `install/arch/fedora-shell.sh` | still works until Fedora is deleted; prints a notice |
| `install/arch/mount-ro.sh`, `tools/backup/linux-backup.sh`, `install/arch/fedora-retire.sh` | read Fedora while it exists |
| `install/arch/arch-grub.sh`, `install/arch/test-entry.sh`, `install/el2/esp-install.sh`, `userspace/boot/arch/book4-boot` | refer to Fedora's GRUB only as the fallback |
