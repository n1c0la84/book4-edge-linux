#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# docs/plan-limine.md step 2: split /boot (sda4, 2 GiB ext4) into
#   sda4  512 MiB ext4, same start, same filesystem UUID (both GRUBs and
#         book4-boot see no difference)
#   sda7  1.5 GiB FAT32 "BOOK4BOOT", type Linux extended boot (XBOOTLDR),
#         in the freed space right after it (before sda5), for Limine
# Run on Arch as your user, in a terminal (sudo asks), after
# fedora-delete.sh and a successful reboot:
#
#   bash install/arch/boot-split.sh          dry run: checks and shows the plan
#   bash install/arch/boot-split.sh --yes    do it
#
# Only touches partition 4 (shrunk at the end) and the free space after it.
# Undo: sfdisk --delete /dev/sda 7, grow partition 4 back to 524288 sectors
# (echo ',524288' | sfdisk -N 4 --no-reread /dev/sda; partx -u /dev/sda),
# resize2fs /dev/sda4; or restore ~/backup/boot-*/sda4.img after that.
set -euo pipefail
DISK=/dev/sda
P4=${DISK}4 P7=${DISK}7
P4_START=92844544     # sectors of 4096 bytes (sfdisk -d, 23 November 2026)
P4_SIZE=524288        # 2 GiB
NEW4=131072           # 512 MiB
P7_START=$((P4_START + NEW4)) P7_SIZE=$((P4_SIZE - NEW4))   # 1.5 GiB, ends where sda5 starts
P5_START=93368832
FS_UUID=3c3204e5-ed67-4e72-b0dc-75b7e3cdb3a5
XBOOTLDR=BC13C2FF-59E6-4262-A352-B275FD6F7172
CONF=/etc/book4/boot.conf
yes=; [ "${1:-}" = --yes ] && yes=1

die() { echo "error: $*" >&2; exit 1; }
[ -e /etc/arch-release ] || die "run this on Arch"
[ "$(id -u)" != 0 ] || die "run as your user (sudo is used inside)"
sudo -v

echo "== checks"
dump=$(sudo sfdisk -d $DISK)
grep -q '^sector-size: 4096$' <<<"$dump" || die "sector size is not 4096"
line=$(grep "^$P4 :" <<<"$dump") || die "no $P4"
[[ $line =~ start=\ *${P4_START}, ]] || die "$P4 does not start at $P4_START: $line"
[[ $line =~ size=\ *${P4_SIZE}, ]] || die "$P4 is not $P4_SIZE sectors (already split?): $line"
grep -q "^$P5_START\$" < <(grep "^${DISK}5 :" <<<"$dump" | sed -E 's/.*start= *([0-9]+),.*/\1/') || die "${DISK}5 does not start at $P5_START"
! grep -q "^$P7 :" <<<"$dump" || die "$P7 exists already"
[ "$(sudo blkid -s UUID -o value $P4)" = "$FS_UUID" ] || die "$P4 is not the /boot filesystem $FS_UUID"
! findmnt -rn -S $P4 >/dev/null || die "$P4 is mounted; unmount it first"
free=$(sudo dumpe2fs -h $P4 2>/dev/null | awk -F: '/^Free blocks/ {gsub(/ /,"",$2); print $2}')
used_mib=$(( (P4_SIZE - free) * 4 / 1024 ))
echo "   $P4: start $P4_START, $P4_SIZE sectors, ${used_mib} MiB used"
[ "$used_mib" -lt 400 ] || die "${used_mib} MiB used on $P4: too much for 512 MiB (run fedora-delete.sh first)"
echo "   plan: $P4 -> $NEW4 sectors (512 MiB, ext4, UUID kept)"
echo "         $P7 start $P7_START, $P7_SIZE sectors (1.5 GiB), XBOOTLDR, FAT32 BOOK4BOOT"

if [ -z "$yes" ]; then echo; echo "Dry run: nothing changed. Run again with --yes."; exit 0; fi

echo "== 1. shrink the filesystem below the new size"
sudo e2fsck -f -p $P4
sudo resize2fs $P4 480M

echo "== 2. shrink partition 4, add partition 7"
sudo sfdisk -d $DISK > ~/backup/sda-gpt-before-split-$(date +%Y%m%d-%H%M).sfdisk
echo ",$NEW4" | sudo sfdisk -N 4 --no-reread --no-tell-kernel $DISK
echo "start=$P7_START, size=$P7_SIZE, type=$XBOOTLDR, name=\"BOOK4BOOT\"" |
    sudo sfdisk --append --no-reread --no-tell-kernel $DISK
sudo partx -u $DISK || true
sudo partx -a $DISK 2>/dev/null || true
udevadm settle
[ -b $P7 ] || die "$P7 did not appear; reboot, then: sudo resize2fs $P4; sudo mkfs.fat -F 32 -n BOOK4BOOT $P7"
[ "$(cat /sys/class/block/sda4/size)" = $((NEW4 * 8)) ] || die "the kernel still sees the old $P4 size; reboot, then: sudo resize2fs $P4"

echo "== 3. grow ext4 to the partition, format FAT32"
sudo resize2fs $P4
sudo e2fsck -f -p $P4
sudo mkfs.fat -F 32 -n BOOK4BOOT $P7

echo "== 4. record and check"
partuuid=$(sudo blkid -s PARTUUID -o value $P7)
fsuuid=$(sudo blkid -s UUID -o value $P7)
if ! grep -q '^LIMINE_PART=' $CONF; then
    printf '%s\n' "# Limine's FAT partition (install/arch/boot-split.sh, docs/plan-limine.md)" \
        "LIMINE_PART=PARTUUID=$partuuid   # filesystem UUID $fsuuid" | sudo tee -a $CONF >/dev/null
fi
sudo sfdisk -l $DISK | sed -n '/^Device/,$p'
sudo book4-boot menu
echo "Done. Reboot through Arch GRUB to check /boot is found as before."
