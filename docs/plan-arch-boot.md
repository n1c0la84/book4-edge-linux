# Plan: kernel builds and GRUB on Arch, Fedora retired (18 November 2026)

ROADMAP section 5, in detail. Nothing here has been done yet.

## What Fedora does today

| Job | Where | Replaced by |
|---|---|---|
| Kernel builds (7.3 daily, 7.2 fallback) | container `install/arch/fedora-shell.sh`, trees in Fedora's home (`~/src/linux-73`, `~/src/patchwork-sleep`) | A: `linux-book4` PKGBUILD, trees in Arch's home |
| Out-of-tree modules (sleep modules, emuec/EC updates, ~20 tools/power/*/build.sh) | same container | A: built against Arch's own headers package |
| GRUB binary | `\EFI\fedora\grubaa64.efi` (Fedora's signed GRUB) | B: Arch's `grub` in `\EFI\arch\` |
| GRUB menu | static `\EFI\fedora\grub.cfg`, written by Fedora's kernel-install hook `99-book4-devicetree.install` (via `install/update-boot-hook.sh`); it sources `/boot/book4-extra.cfg` (test entries) | B: the same generator ported to an Arch pacman hook |
| `/boot` | sda4, 2 GB ext4, Fedora's (1.4 GB used: Fedora and Arch kernels mixed) | B: sda4 mounted at `/boot` on Arch |
| EL2 chain hand-over | `\EFI\book4-el2\startup.nsh` starts `\EFI\fedora\grubaa64.efi` | B: tries `\EFI\arch\grubaa64.efi` first, Fedora's as fallback |

Facts: ESP 256 MB, 119 MB free (no kernels there). Firmware entries:
0003 "Book4 EL2 (slbounce)" (default, Shell + startup.nsh), 0001 Fedora,
0000 Windows, 0002 OpenBSD. Arch has gcc 16, make, cpio, efibootmgr,
dtc; missing `bc`, `pahole`, `grub`. `\EFI\book4\arm64-efi\` holds 7
GRUB modules from an October experiment.

## A. Kernel builds on Arch (no boot change at all)

**Test passed, 18 November:** `packages/linux-book4/PKGBUILD` with
`BOOK4_SUFFIX=-book4p` built on Arch in 27 minutes (gcc 16.1.1; tree
`~/src/linux-book4`, config copied from Fedora's `~/src/linux-73`, as the
running kernel has no /proc/config.gz); `linux-book4p` (5905 modules, the
DTB, the six sleep modules in extra/) and `linux-book4p-headers`.
`tools/kernel/install-book4-kernel.sh book4p` installed it (pacman -U,
initramfs, /boot, EL2 DTB, entry; test-entry.sh learned to work from the
arch-45 copy). Boot: pacman-owned, DSPs, Iris, sound, mic, KVM,
fingerprint, errors as usual; nap 97.2 %. Next: the same as
`linux-book4` (7.3.4-book4) replacing the unpackaged install from
build-73-kernel.sh, then remove book4p.

1. `pacman -S --needed base-devel bc pahole` (+ `xmlto`/`python` if the
   build asks).
2. Clone `book4/7.3` into `~/src/linux-book4` (blobless, ~2 GB +
   ~6 GB build output). Copy `.config` from `/proc/config.gz`.
3. `packages/linux-book4/PKGBUILD` (in this repo): builds from that
   tree with `LOCALVERSION` empty and `CONFIG_LOCALVERSION=-book4`;
   packages `linux-book4` (Image, modules, DTBs under
   `/usr/lib/modules/<rel>/`) and `linux-book4-headers` (for module
   builds). The kernel and initramfs go to /boot via a pacman hook (see B);
   until B, the package installs only under /usr and the existing
   `build-73-kernel.sh` install step copies to sda4 as today.
4. `book4-sleep-modules`: the out-of-tree sleep modules as a DKMS
   package (rebuilt automatically for every kernel) or built inside the
   PKGBUILD; same for the tools/power helpers, which then build with
   `make -C /usr/lib/modules/<rel>/build`.
5. Check: build, install next to the current kernel under a different
   suffix first (e.g. `-book4p`), boot it from a test entry, compare with
   check-73.sh; then make the package the way 7.3 is built.
6. Move the scripts off `fedora-shell.sh` one by one (the list:
   `grep -rl fedora-shell.sh install tools`).

Cost: one session to write and test, one long build (~1 h, hot: on the
charger), one reboot. Risk: none for booting (GRUB and /boot untouched;
the daily kernel stays installed).

## B. Arch's GRUB replaces Fedora's

1. Mount sda4 at `/boot` on Arch (fstab, `noauto,x-systemd.automount`
   first). Fedora's files stay for now.
2. `pacman -S grub`; `grub-install --target=arm64-efi --efi-directory=/efi
   --bootloader-id=arch --no-nvram` (no firmware entry yet; files in
   `\EFI\arch\`, modules in `/boot/grub/`).
3. Port the generator (`99-book4-devicetree.install`) to a pacman hook
   `book4-grub-cfg` writing `/boot/grub/grub.cfg`: same entries (daily
   7.3, 7.2 fallback, EL1 variants), same `devicetree` lines, still
   sourcing `/boot/book4-extra.cfg`, so `test-entry.sh` keeps working.
   Not grub-mkconfig (it does not handle per-kernel DTBs).
4. Test without changing anything: a second EL2 Shell directory
   `\EFI\book4-el2-arch\` (copies of Shell/qebspil/slbounce/tcblaunch,
   a startup.nsh that starts `\EFI\arch\grubaa64.efi`) and a firmware
   entry for it placed last in BootOrder; boot it once from the
   firmware's boot menu. Same for EL1 (an entry straight to
   `\EFI\arch\grubaa64.efi`).
5. When it boots both kernels at EL2 and EL1, switch: the main
   `startup.nsh` tries `\EFI\arch\` first and falls back to
   `\EFI\fedora\`. Fedora's GRUB stays on the ESP (hard rule: never
   delete from the ESP).

Cost: one session, 3-4 reboots. Risk: low, thanks to step 4; the
fallback at every point is the current default firmware entry, untouched
until step 5, and after step 5 still Fedora's GRUB via the fallback.

## C. Retire Fedora

After A and B have run for a few days: back up anything wanted from
Fedora's home, delete the `root` and `home` subvolumes (~25 GB), remove
Fedora's kernels and BLS entries from sda4, the Fedora firmware entry
(0001) only if wanted. `\EFI\fedora\` stays on the ESP.

## Order and reboots

A (1 reboot) -> B (3-4 reboots) -> a few days -> C (no reboot).
