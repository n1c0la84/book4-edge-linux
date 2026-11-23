# Plan: Limine beside Arch GRUB, on a split /boot

Written 22 November 2026, to execute later. ROADMAP section 5 item 5
("Optional, later: Limine"). Same rules as the GRUB move: a second firmware
entry first, Arch GRUB stays the default until Limine has run for a few days,
nothing on the ESP is deleted.

## Why

- Closer to stock Omarchy (ROADMAP goal): Omarchy installs Limine with one
  UKI per kernel; its Limine tools (`omarchy-refresh-limine`,
  `limine-snapper-sync`) are on our "never run" list only because we boot GRUB.
- Bootable snapper snapshots from the menu.
- Known to work on this hardware: the Omarchy nightly ISO booted the 14" with
  Limine (17 November, EL1, UKI with `DeviceTreeAuto`, no `cutmem`).

## What this machine needs from any bootloader

1. **The EL2 chain**: firmware entry -> UEFI Shell -> `startup.nsh` loads
   qebspil and slbounce -> the bootloader. Limine is an EFI program like
   GRUB, so the Shell can start it instead (`userspace/el2/startup.nsh`).
2. **Our EL2 device tree per entry**, never Omarchy's plain one: slbounce
   switches only for a DTB with the GPU zap shader disabled, and qebspil starts
   the DSPs only for DTBs that mark them `qcom,broken-reset`. A UKI with
   `DeviceTreeAuto` picks the stock 14" DTB, so either Limine's `dtb_path`
   per entry, or UKIs built with only our EL2 DTB.
3. **`cutmem 0x8800000000 0x8fffffffff`** (bootstrap.md: instant reboots
   without it, on 7.2-era kernels). Limine has no such command. The nightly
   ISO booted without it on 7.3 at EL1; whether our EL2 boot needs it is
   unknown. If it does: a `reserved-memory` `no-map` node for that range in
   our DTB (book4-boot's DTB step), which works with any bootloader.
4. **A FAT filesystem for kernels**: Limine reads only FAT (and ISO9660),
   and our /boot (sda4) is ext4. The ESP (sda1, 260 MB, ~116 MB free on
   19 Nov) is too small for more than one ~100 MB UKI.

## Current /boot (sda4, measured 22 November)

2 GB ext4, 1.3 GB used, 583 MB free. Not mounted normally (`book4-boot` and
`test-entry.sh` mount it when needed). Both GRUBs find it by filesystem UUID.

| Contents | Size | Status |
|---|---|---|
| Fedora rescue initramfs + vmlinuz (2 machine ids) | ~585 MB | Fedora retired, delete |
| Fedora kernel `7.2.0-61.fc45` (initramfs, vmlinuz, `dtb-7.2.0-61.fc45.aarch64`, System.map) | ~200 MB | only for Fedora's own entry, delete with Fedora |
| `7.2.7-book4` (EL1) vmlinuz + `initramfs-7.2.7-book4.img` + `.prev` copies + `initramfs-7.2.7-book4-arch-ufstest.img` | ~240 MB | leftovers, check each against `book4-boot menu --print` |
| Daily `7.3.4-book4` + fallback `7.2.7-book4s` + `grub/` + `dtb-*/`, `dtb-test/` | ~220 MB | keep |

## Steps

### 0. Before

- Run the pending items that touch boot first, or together:
  the Omarchy-kernel test (arewearmyet#10; script prepared
  22 November, entry "omarchy-el2"). It can also become one of the first
  Limine entries in step 3.
- Back up sda4 whole: `dd if=/dev/sda4 of=~/backup/sda4-YYYYMMDD.img
  bs=4M status=progress` (2 GB; as root, sda4 unmounted).
- `efibootmgr -v` and the ESP listing (`ls -R /efi/EFI`) saved to the
  backup folder.

### 1. Clean sda4 (with the Fedora deletion, ROADMAP "Fedora deletion")

Script: `install/arch/fedora-delete.sh` (dry run by default, `--yes` to act;
also does step 0's backup and deletes the subvolumes `root`, `home` and
`arch`). **Keep `/vmlinuz-7.2.7-book4`:** Fedora's GRUB (`\EFI\fedora\grub.cfg`,
the fallback) finds /boot with `search --file /vmlinuz-7.2.7-book4`; without
that file the fallback has no menu. After the deletion its only working entry
is the sourced `book4-extra.cfg` test entry on arch-45.

- Delete the Fedora rescue files, the `fc45` kernel set and the leftovers
  above, after checking that `book4-boot menu --print` and
  `test-entry.sh list` reference none of them.
- Fedora's GRUB on the ESP stays (`\EFI\fedora\`, never delete from the
  ESP); its entry still boots our Arch kernels from sda4's `grub.cfg`.
- Then `book4-boot menu`. Reboot once through Arch GRUB and once through the
  Fedora GRUB fallback to prove both menus still work.
- Expected use afterwards: ~300 MB.

### 2. Split sda4: 512 MiB ext4 + 1.5 GiB second ESP

**Decided 23 November (owner): sda7 is a second ESP** (type EFI System,
FAT32 `BOOK4ESP`), mounted at `/boot` as on stock Omarchy, where the ESP is
`/boot` and Limine, `limine.conf` and the UKIs live together; Omarchy's own
Limine tools then have the best chance to work unchanged. sda1 stays the
firmware's and Windows' ESP and keeps the UEFI Shell chain (`book4-el2` no
longer falls back to a `/boot` labelled BOOK4ESP). The old `/boot` folder of
the root filesystem (one stray initramfs from October) moves to ~/backup.

**Step 1 done 23 November** (fedora-delete.sh: /boot at 222 MB). **Step 2 done 23 November 11:38**: sda4 512 MiB (180 MB free), sda7 `BOOK4ESP` UUID 7A97-F511 at /boot. Script for
this step: `install/arch/boot-split.sh` (dry run by default, `--yes`).
Geometry (4096-byte sectors): sda4 start 92844544, 524288 -> 131072
sectors; sda7 start 92975616, 393216 sectors, ends at sda5's start 93368832.

All from the running system, sda4 unmounted, as root (one user-run script,
`install/arch/boot-split.sh`, to be written; `--dry-run` first):

1. `e2fsck -f /dev/sda4`, then `resize2fs /dev/sda4 480M` (below the
   partition, as a safety margin).
2. Shrink partition 4 to 512 MiB with `sfdisk` (start unchanged: the
   filesystem UUID and contents stay, so both GRUBs see no difference),
   then `resize2fs /dev/sda4` to fill it exactly.
3. New partition 7 in the freed space (physically between sda4 and sda5),
   type EFI System (`c12a7328-f81f-11d2-ba4b-00a0c93ec93b`),
   `mkfs.fat -F 32 -n BOOK4ESP`; fstab `/boot vfat umask=0077,nofail`.
4. `partprobe`; record the new PARTUUID and filesystem UUID in
   `/etc/book4/boot.conf` (new `LIMINE_PART=`).
5. Check: `book4-boot menu --print` unchanged, `e2fsck -f /dev/sda4`
   clean, a normal reboot through Arch GRUB.

### 3. Limine by hand, second firmware entry

**Prepared 23 November:** `install/arch/limine-test.sh` (`setup` dry run,
`setup --yes`, `next` for a one-time BootNext, `status`) and
`install/limine/startup.nsh`. Findings that shaped it:
- Limine 12.11 (extra; the local package database of 19 Nov still named
  12.10, gone from the mirror: run `book4-update` first). Config keys
  checked in its CONFIG.md: `protocol: linux|efi`, `path`, `module_path`,
  `dtb_path`, `cmdline`, `boot():` (the volume with the config) and
  `guid(<partition GUID>):`. Config search on the volume of the Limine
  binary: `<app dir>/limine.conf`, then `/boot/limine/limine.conf`,
  `/boot/limine.conf`, `/limine/limine.conf`, `/limine.conf`; stock Omarchy
  uses `/boot/limine.conf` with the ESP at /boot, i.e. `\limine.conf` on
  the ESP, as here.
- **The DTB must reach the EFI configuration table**, where slbounce and
  qebspil read it at ExitBootServices. A UKI does that (systemd-stub installs
  its `.dtb`), so entry 1 is a UKI with only our EL2 DTB (ukify
  `--devicetree`), protocol `efi`. Whether Limine's own `linux` protocol with
  `dtb_path` does it is not documented: entry 2 tests it.
- Omarchy's Qualcomm UKIs list every x1/hamoa DTB for `DeviceTreeAuto` but
  skip `*-el2.dtb` (`install/hardware/qualcomm/dtb-uki.sh`): stock picks the
  EL1 tree, so for EL2 the UKI must be ours.
- `limine-mkinitcpio-hook` (Omarchy's repo, 1.40) replaces the mkinitcpio
  pacman hook (`/etc/pacman.d/hooks/90-mkinitcpio-install.hook`), adds a
  `/usr/local/bin/mkinitcpio` wrapper and may change BootOrder through
  efibootmgr (`UEFI_BOOT_ORDER`): not installed in step 3, only `limine` and
  `systemd-ukify`. Step 6 decides about it.

- `pacman -S limine` (extra, 12.x on 22 November). Read
  `/usr/share/doc/limine/CONFIG.md` for the installed version: path syntax
  (`boot()`, `guid()`/`uuid()`), the `cmdline` key and `dtb_path`; the plan
  below assumes those names.
- sda1 (firmware ESP): new folder `\EFI\book4-el2-limine\` with a copy of
  the UEFI Shell (`Shellaa64.efi` from book4-edge-el2) and a `startup.nsh`
  like ours that loads
  `\EFI\book4-el2-arch\qebspilaa64.efi` and `slbounce.efi` (slbounce looks
  for tcblaunch.exe in `\EFI\book4-el2-arch\`) and then starts Limine
  from the second ESP (the fs with Limine's binary, as the loop in our
  startup.nsh finds files), with Arch GRUB as fallback if Limine is missing
  or returns. A few MB on sda1.
- sda7 (`/boot`): Limine's `BOOTAA64.EFI` and `limine.conf` where Omarchy
  puts them (check its `omarchy-refresh-limine` / limine-entry-tool paths).
- Copy the daily kernel set to `/boot`: `vmlinuz-7.3.4-book4`,
  `initramfs-7.3.4-book4-arch.img`, both DTBs from `dtb-7.3.4-book4/`.
- `limine.conf`: one EL2 entry (EL2 DTB, the cmdline from
  `/etc/book4/boot.conf` plus `root=`, `rootflags=subvol=` and
  `id_aa64mmfr0.ecv=1` as book4-boot adds them), one EL1 entry (EL1 DTB),
  and the old fallback `7.2.7-book4s` EL2 entry.
- Firmware entry "Omarchy (EL2, Limine)" with `efibootmgr --create`, not in
  front of BootOrder; test with `efibootmgr --bootnext`.
- **Tests** (record each in STATE.md):
  (23 Nov: test 1 boot part passed with the UKI entry: EL2, KVM, DSPs,
  sound, no `cutmem`; suspend and the other entries still open)
  1. EL2 boot: `book4-el2 status`, KVM present, ADSP/CDSP attached, sound,
     sleep (`cxsd` like the GRUB boot), `BootCurrent` the new entry.
  2. `cutmem`: the boot works without it, then a day of normal use and a
     few suspends. If it reboots instantly: add the `reserved-memory`
     node (requirement 3) and retest.
  3. EL1 entry boots.
  4. Return to GRUB: Limine's menu exit, and BootNext unset -> GRUB again.

### 4. Generate Limine's config from book4-boot

- `book4-boot` gets a Limine output next to GRUB's: for each Book4 kernel it
  already handles, copy vmlinuz, initramfs and both DTBs to the FAT
  partition and write `limine.conf` (EL2 and EL1 entries, default
  `DEFAULT_PKG`, test entries from a `book4-extra` equivalent). Prune what it
  wrote (mark file, as for `/dtb-REL/`).
- Kernels without a Book4 DTB (`linux-omarchy`) keep being skipped, unless
  an explicit EL2 DTB is configured for them (the omarchy-el2 case).
- `test-entry.sh` learns to write Limine test entries.
- Ship in book4-edge-boot; the pacman hooks stay the same.

### 5. Make Limine the default

**Done 23 November by the owner's choice, before step 4** (BootOrder
0001,0004,0003,0000,0002). Step 4 is now urgent: kernel updates reach only GRUB.

After a few days on the Limine entry: BootOrder Limine first, Arch GRUB
second, Fedora GRUB third. `startup.nsh` of the Limine folder keeps falling
back to Arch GRUB. Update docs/install.md, ROADMAP section 5 and STATE.md.

### 6. Later: Omarchy's way (UKIs, snapshots)

- UKIs on `/boot` (sda7) built with only our EL2 DTB (ukify
  `--devicetree`), so `DeviceTreeAuto` cannot pick the stock DTB.
- Check whether Omarchy's `limine-mkinitcpio-hook` / `limine-entry-tool`
  can carry our DTB and the EL2 cmdline; if yes, drop our generator for
  theirs and lift the "never run `omarchy-refresh-limine`" rule; if not,
  keep book4-boot as the generator.
- `limine-snapper-sync` for bootable snapshots, sized against the 1.5 GB
  partition (one kernel set ~100 MB).

## Undo

- Limine entry: `efibootmgr -b XXXX -B`; the `\EFI\book4-el2-limine\` folder
  can stay (never delete from the ESP without the owner).
- Split: remove the `/boot` line from fstab, then partition 7 can be deleted and partition 4 grown back
  (`sfdisk` + `resize2fs`); or restore the dd image.
- Cleanup: the dd image from step 0 holds the deleted Fedora files.
