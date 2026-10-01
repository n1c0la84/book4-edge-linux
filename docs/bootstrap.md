# Getting the machine to boot at all

Notes from the initial bring-up (September 2026). The full history and scripts
live with the workstation copy of this project; this is the distilled version.

## Boot chain

- UEFI (no Secure Boot) -> Fedora's signed `grubaa64.efi` on the shared ESP ->
  a **static** `EFI/fedora/grub.cfg` -> kernel + initramfs from `/boot` (ext4),
  device tree passed with GRUB's `devicetree` command.
- Fedora's signed aarch64 GRUB does not do multi-initrd.
- Linux cannot write EFI variables here (QSEECOM not allowlisted for this
  machine in the stock kernel), so there is no NVRAM boot entry; the firmware
  boots `\EFI\BOOT\bootaa64.efi`, or pick the disk from the firmware boot menu.
- The ESP is shared with Windows: only add files, never delete.

## Load-bearing details

- `cutmem 0x8800000000 0x8fffffffff` in grub.cfg. Without it: instant reboots.
- The DTB must be padded (`dtc -p 8192`), or GRUB cannot write
  `linux,initrd-start` into `/chosen` and the kernel dies with
  `unknown-block(0,0)`.
- `cma=256M` on the command line (ath12k).
- `mem_sleep_default=s2idle`: `deep` suspend never resumes.
- `/lib` is a symlink to `/usr/lib`. Any `tar` without `--keep-directory-symlink`
  replaces it and nothing executes any more.
- The static grub.cfg names kernels explicitly. The kernel-install hook
  [`userspace/boot/99-book4-devicetree.install`](../userspace/boot/99-book4-devicetree.install)
  regenerates it on every kernel add/remove, keeps a pinned known-good kernel
  (`/etc/book4/default-kernel`) as the default, and can add an alternative-DTB
  entry (`/etc/book4/test-dtb`).
- On Fedora, DKMS regenerates the initramfs after each module install
  (`dracut --regenerate-all --force`); the DSP firmware stays in thanks to the
  dracut snippet.

## Device tree history

1. Our own DTB, compiled from the linux-arm-msm v6 series rebased onto 7.2.6
   `hamoa.dtsi` (`dts/*.book4-own.dtb`). Booted, but declared `pmic-glink`
   (which cannot work here), WSA884x speakers at the wrong addresses, and USB
   redrivers on the wrong buses.
2. Anatase's DTB (`dts/*.anatase.dtb`), built from their `anatase-7.2` sources.
   Correct hardware description. Requires `samsung-emuec` for the display to
   come up: without it the USB-C DP chains never complete and `msm` never binds,
   so the screen stays black ("boot the DTB alone first" does not work).
