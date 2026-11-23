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

### 2. Split sda4: 512 MiB ext4 + ~1.5 GiB FAT32

All from the running system, sda4 unmounted, as root (one user-run script,
`install/arch/boot-split.sh`, to be written; `--dry-run` first):

1. `e2fsck -f /dev/sda4`, then `resize2fs /dev/sda4 480M` (below the
   partition, as a safety margin).
2. Shrink partition 4 to 512 MiB with `sfdisk` (start unchanged: the
   filesystem UUID and contents stay, so both GRUBs see no difference),
   then `resize2fs /dev/sda4` to fill it exactly.
3. New partition 7 in the freed space (physically between sda4 and sda5),
   type "Linux extended boot" (XBOOTLDR,
   `bc13c2ff-59e6-4262-a352-b275fd6f7172`), `mkfs.fat -F 32 -n BOOK4BOOT`.
4. `partprobe`; record the new PARTUUID and filesystem UUID in
   `/etc/book4/boot.conf` (new `LIMINE_PART=`).
5. Check: `book4-boot menu --print` unchanged, `e2fsck -f /dev/sda4`
   clean, a normal reboot through Arch GRUB.

### 3. Limine by hand, second firmware entry

- `pacman -S limine` (extra, 12.x on 22 November). Read
  `/usr/share/doc/limine/CONFIG.md` for the installed version: path syntax
  (`boot()`, `guid()`/`uuid()`), the `cmdline` key and `dtb_path`; the plan
  below assumes those names.
- ESP: new folder `\EFI\book4-el2-limine\` with a copy of the UEFI Shell
  (`Shellaa64.efi` from book4-edge-el2), `BOOTAA64.EFI` from the limine
  package, `limine.conf`, and a `startup.nsh` like ours that loads
  `\EFI\book4-el2-arch\qebspilaa64.efi` and `slbounce.efi` (slbounce looks
  for tcblaunch.exe in `\EFI\book4-el2-arch\`) and then starts Limine, with
  Arch GRUB as fallback if Limine is missing or returns. A few MB on the ESP.
- Copy the daily kernel set to the FAT partition: `vmlinuz-7.3.4-book4`,
  `initramfs-7.3.4-book4-arch.img`, both DTBs from `dtb-7.3.4-book4/`.
- `limine.conf`: one EL2 entry (EL2 DTB, the cmdline from
  `/etc/book4/boot.conf` plus `root=`, `rootflags=subvol=` and
  `id_aa64mmfr0.ecv=1` as book4-boot adds them), one EL1 entry (EL1 DTB),
  and the old fallback `7.2.7-book4s` EL2 entry.
- Firmware entry "Omarchy (EL2, Limine)" with `efibootmgr --create`, not in
  front of BootOrder; test with `efibootmgr --bootnext`.
- **Tests** (record each in STATE.md):
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

After a few days on the Limine entry: BootOrder Limine first, Arch GRUB
second, Fedora GRUB third. `startup.nsh` of the Limine folder keeps falling
back to Arch GRUB. Update docs/install.md, ROADMAP section 5 and STATE.md.

### 6. Later: Omarchy's way (UKIs, snapshots)

- UKIs on the FAT partition built with only our EL2 DTB (ukify
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
- Split: partition 7 can be deleted and partition 4 grown back
  (`sfdisk` + `resize2fs`); or restore the dd image.
- Cleanup: the dd image from step 0 holds the deleted Fedora files.
