# Fedora retired (part C, from 19 November 2026)

Fedora is no longer needed for anything: the kernel is built and packaged on
Arch (`packages/linux-book4`, plan part A), Arch's own GRUB boots by default
with a menu written by `book4-boot` (part B), and its data is archived into
Arch (`install/arch/fedora-retire.sh archive`). **Fedora is not deleted yet.**
It still boots: as "Fedora Linux (Fedora's GRUB menu)" in the Arch GRUB menu,
and through the firmware entries "Omarchy (EL2, Fedora GRUB, fallback)" and
"Fedora GRUB (EL1)".

Deletion approved by the owner 23 November 2026, together with the pre-4.5
Arch copy (`arch`): `install/arch/fedora-delete.sh` (dry run first, then
`--yes`). What deleting it will mean later (not done, needs the owner's go): the
`root` and `home` btrfs subvolumes (~25 GB, minus what the archive's reflinks
keep), Fedora's kernels, initramfs and BLS entries on sda4 (`/grub2`,
`/loader`), the Fedora GRUB menu entry and, if wanted, firmware entry
"Fedora GRUB (EL1)". `\EFI\fedora\` stays on the ESP (hard rule), so the
fallback firmware entry keeps working as long as sda4 keeps the 7.3 kernel.

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
