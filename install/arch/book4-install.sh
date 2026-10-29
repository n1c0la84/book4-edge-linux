#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# book4-install (on the live ISO, install/arch/live-iso.sh): reset Linux on
# the Galaxy Book4 Edge's internal disk. Wipes every Linux partition (on this
# machine sda4, Fedora's /boot, and sda5, the btrfs with Fedora and Arch) and
# puts the live ISO's system into one new btrfs partition (subvolume arch,
# kernel in /boot/book4), with its own boot chain (lib/book4-grub.sh) on the
# ESP. Windows, its partitions and its boot files stay. On the ESP files are
# only added or replaced (\EFI\book4\, \EFI\book4-el2\, \firmware\...),
# nothing is deleted; \EFI\fedora stays, unused.
#
#   sudo book4-install          show the plan, change nothing
#   sudo book4-install --wipe   do it (asks you to type WIPE LINUX)
#
# The installed system is the ISO's: same user and password, sshd off, no
# Wi-Fi connections. Firmware boot entry "Book4" (GRUB) goes first; the
# menu's EL2 entry chainloads the UEFI Shell in \EFI\book4-el2\.
set -euo pipefail
LIB=/usr/local/lib/book4
SFS=/run/book4live/iso/live/airootfs.sfs
DISK=${DISK:-}
T=/mnt/book4-target
ESPM=/mnt/book4-esp
EL2DIR=EFI/book4-el2
FWDIR=firmware/qcom/x1e80100/SAMSUNG/galaxy-book4-edge
FWSRC=/usr/lib/firmware/updates/qcom/x1e80100/SAMSUNG/galaxy-book4-edge
LABEL="Book4"
# GPT types that are Windows' (kept) and the new root's.
KEEP_TYPES="c12a7328-f81f-11d2-ba4b-00a0c93ec93b e3c9e316-0b5c-4db8-817d-f92df00215ae
            ebd0a0a2-b9e5-4433-87c0-68b6b72699c7 de94bba4-06d1-4d40-a16a-bfd50179d6ac"
ESP_TYPE=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
ROOT_TYPE=b921b045-1df0-41c3-af44-4c6f280d3fae   # Linux root (arm64)

(( EUID == 0 )) || { echo "Run it with sudo." >&2; exit 1; }
[ -s "$SFS" ] || { echo "Not on the Book4 live ISO ($SFS missing)." >&2; exit 1; }
# shellcheck source=/dev/null
. "$LIB/kernel-args"         # KVER EL2ARGS EL1ARGS HOST_NAME
# shellcheck source=lib/book4-grub.sh
. "$LIB/book4-grub.sh"
WIPE=0
case ${1:-} in --wipe) WIPE=1 ;; "") ;; *) sed -n '12,13p' "$0" | sed 's/^# //' >&2; exit 1 ;; esac

# The internal disk: the only non-USB disk (with the stick in, the UFS
# disk is not always sda).
if [ -z "$DISK" ]; then
    mapfile -t disks < <(lsblk -dnpo NAME,TYPE,TRAN | awk '$2 == "disk" && $3 != "usb" && $1 !~ /^\/dev\/(loop|zram|sr)/ {print $1}')
    (( ${#disks[@]} == 1 )) || { echo "Found ${#disks[@]} internal disks (${disks[*]}); name it: sudo DISK=/dev/sdX book4-install" >&2; exit 1; }
    DISK=${disks[0]}
fi
echo "== disk $DISK"
[ -b "$DISK" ] && [ "$(lsblk -dno TYPE "$DISK")" = disk ] || { echo "$DISK is not a disk." >&2; exit 1; }
[ "$(lsblk -dno TRAN "$DISK")" != usb ] || { echo "$DISK is a USB disk, not the internal one." >&2; exit 1; }
iso_disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE /run/book4live/iso)" 2>/dev/null || true)
[ -z "$iso_disk" ] || [ "/dev/$iso_disk" != "$DISK" ] || { echo "$DISK holds the live ISO." >&2; exit 1; }
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL "$DISK"

# One line per partition: node start size type fstype
mapfile -t PARTS < <(sfdisk -J "$DISK" | python3 -I -c '
import json, sys
for p in json.load(sys.stdin)["partitiontable"]["partitions"]:
    print(p["node"], p["start"], p["size"], p["type"].lower())')
keep=() wipe=() esp= first_wipe=
for line in "${PARTS[@]}"; do
    read -r node start size type <<<"$line"
    fs=$(lsblk -no FSTYPE "$node" 2>/dev/null || true)
    if [[ " $KEEP_TYPES " == *" $type "* ]] || [ "$fs" = ntfs ]; then
        keep+=("$node")
        [ "$type" = "$ESP_TYPE" ] && esp=$node
        [ -z "$first_wipe" ] || { echo "$node ($type) lies after a Linux partition; refusing (expected Linux at the end)." >&2; exit 1; }
    else
        wipe+=("$node")
        [ -n "$first_wipe" ] || first_wipe=$start
    fi
done
[ -n "$esp" ] || { echo "No EFI system partition on $DISK." >&2; exit 1; }
(( ${#wipe[@]} )) || { echo "No Linux partition to wipe on $DISK." >&2; exit 1; }
for p in "${wipe[@]}"; do
    ! findmnt -rno TARGET -S "$p" >/dev/null || { echo "$p is mounted; unmount it first." >&2; exit 1; }
    ! grep -q "^$p " /proc/swaps || { echo "$p is in use as swap." >&2; exit 1; }
done

echo
echo "Plan:"
echo "  keep:   ${keep[*]}   (ESP $esp: files added/replaced only)"
echo "  WIPE:   ${wipe[*]}"
for p in "${wipe[@]}"; do echo "          $p  $(lsblk -no SIZE,FSTYPE,LABEL "$p" | head -1)"; done
echo "  create: one btrfs partition from sector $first_wipe to the end, subvolume arch"
echo "  system: $SFS (kernel $KVER), hostname $HOST_NAME"
echo "  ESP:    \\EFI\\book4\\ (GRUB), \\$EL2DIR\\ (UEFI Shell, qebspil, slbounce, tcblaunch), \\${FWDIR//\//\\}\\"
echo "  UEFI:   boot entry \"$LABEL\" first in BootOrder"
(( WIPE )) || { echo; echo "Nothing changed. To do it: sudo book4-install --wipe"; exit 0; }

echo
read -r -p "This erases ${wipe[*]} (Arch, Fedora and everything on them) for good. Type WIPE LINUX: " ok
[ "$ok" = "WIPE LINUX" ] || { echo "Aborted."; exit 1; }

cleanup() {
    sync
    for d in "$T/boot/efi" "$T" "$ESPM"; do mountpoint -q "$d" && umount "$d" || true; done
}
trap cleanup EXIT

echo "== 1. partitions"
nums=()
for p in "${wipe[@]}"; do nums+=("$(cat "/sys/class/block/$(basename "$p")/partition")"); done
wipefs -qa "${wipe[@]}"
sfdisk -q --no-reread --delete "$DISK" "${nums[@]}"
echo "start=$first_wipe, type=$ROOT_TYPE, name=\"book4\"" | sfdisk -q --no-reread --append "$DISK"
partprobe "$DISK" 2>/dev/null || partx -u "$DISK"
udevadm settle
NEW=$(sfdisk -J "$DISK" | python3 -I -c '
import json, sys
for p in json.load(sys.stdin)["partitiontable"]["partitions"]:
    if p["start"] == int(sys.argv[1]): print(p["node"])' "$first_wipe")
[ -b "$NEW" ] || { echo "The new partition did not appear." >&2; exit 1; }
lsblk -o NAME,SIZE,PARTLABEL "$DISK"

echo "== 2. btrfs on $NEW"
wipefs -qa "$NEW"
mkfs.btrfs -q -f -L book4 "$NEW"
RUUID=$(blkid -s UUID -o value "$NEW")
mkdir -p "$T"
mount "$NEW" "$T"
btrfs -q subvolume create "$T/arch"
umount "$T"
mount -o compress=zstd:1,subvol=arch "$NEW" "$T"

echo "== 3. system"
unsquashfs -f -q -d "$T" "$SFS"
rm -f "$T/etc/mkinitcpio.conf.d/book4-live.conf"
systemd-id128 new > "$T/etc/machine-id"
echo "$HOST_NAME" > "$T/etc/hostname"
cat > "$T/etc/fstab" <<EOF
# Installed by book4-install from the live ISO ($(date +%F)).
UUID=$RUUID / btrfs rw,relatime,compress=zstd:1,subvol=/arch 0 0
EOF
systemd-nspawn -q -D "$T" mkinitcpio -k "$KVER" -g /boot/book4/initramfs.img
systemd-nspawn -q -D "$T" --pipe lsinitcpio /boot/book4/initramfs.img | grep -q '/ufs-qcom\.ko' ||
    { echo "ufs-qcom.ko missing from the new initramfs." >&2; exit 1; }
mkdir -p "$T/boot/grub"
book4_grub_cfg "Book4" "$KVER" /arch/boot/book4 "root=UUID=$RUUID rootflags=subvol=arch ro" "$EL2ARGS" "$EL1ARGS" \
    > "$T/boot/grub/grub.cfg"

echo "== 4. ESP $esp"
mkdir -p "$ESPM"
mount "$esp" "$ESPM"
G=$(mktemp -d)
book4_grub_embed "search --no-floppy --fs-uuid --set=root $RUUID" \
    'search --no-floppy --set=esp --file /EFI/book4/grub-el2.efi' '($root)/arch/boot/grub' > "$G/embed.cfg"
book4_grub_embed "search --no-floppy --fs-uuid --set=root $RUUID" \
    'search --no-floppy --set=esp --file /EFI/book4/grub-el2.efi' '($root)/arch/boot/grub' el2 > "$G/embed-el2.cfg"
grub-mkstandalone -O arm64-efi -o "$G/grubaa64.efi" --modules="$BOOK4_GRUB_MODULES" "boot/grub/grub.cfg=$G/embed.cfg"
grub-mkstandalone -O arm64-efi -o "$G/grub-el2.efi" --modules="$BOOK4_GRUB_MODULES" "boot/grub/grub.cfg=$G/embed-el2.cfg"
need=$(( $(du -ck "$G"/*.efi /usr/lib/book4/efi/* "$FWSRC"/* | tail -1 | cut -f1) + 1024 ))
have=$(( $(df -k --output=avail "$ESPM" | tail -1) + $(du -sk "$ESPM/EFI/book4" "$ESPM/$EL2DIR" "$ESPM/$FWDIR" 2>/dev/null | awk '{s+=$1} END {print s+0}') ))
(( have > need )) || { echo "Not enough space on the ESP (${have} KiB, need ${need} KiB)." >&2; exit 1; }
mkdir -p "$ESPM/EFI/book4" "$ESPM/$EL2DIR" "$ESPM/$FWDIR"
install -m 644 "$G/grubaa64.efi" "$G/grub-el2.efi" "$ESPM/EFI/book4/"
install -m 644 /usr/lib/book4/efi/* "$ESPM/$EL2DIR/"
# The old startup.nsh started Fedora's GRUB; kept next to the new one.
if [ -e "$ESPM/$EL2DIR/startup.nsh" ] && ! cmp -s "$ESPM/$EL2DIR/startup.nsh" "$LIB/startup-installed.nsh"; then
    cp "$ESPM/$EL2DIR/startup.nsh" "$ESPM/$EL2DIR/startup.nsh.before-book4-install"
fi
install -m 644 "$LIB/startup-installed.nsh" "$ESPM/$EL2DIR/startup.nsh"
install -m 644 "$FWSRC"/{qcadsp8380.mbn,adsp_dtbs.elf,qccdsp8380.mbn,cdsp_dtbs.elf} "$ESPM/$FWDIR/"
rm -rf "$G"
sync

echo "== 5. UEFI boot entry"
if [ -n "$(ls /sys/firmware/efi/efivars 2>/dev/null | head -1)" ]; then
    part=$(cat "/sys/class/block/$(basename "$esp")/partition")
    old=$(efibootmgr | awk -v l="$LABEL" '/^Boot[0-9A-F]{4}/ { n = substr($0, 5, 4); t = substr($0, 10)
        sub(/^\* ?/, "", t); sub(/\t.*/, "", t); if (t == l) print n }')
    for n in $old; do efibootmgr -q -b "$n" -B; done
    # --create puts the new entry first in BootOrder.
    efibootmgr -q --create --disk "$DISK" --part "$part" --label "$LABEL" --loader '\EFI\book4\grubaa64.efi'
    efibootmgr | sed -n '1,/^Boot/p;/Book4/p' | sort -u
else
    echo "   No EFI variables on this boot: no boot entry written. Boot it with F10 ->"
    echo "   \"Book4 EL2 (slbounce)\" (now starts this GRUB), or rerun book4-install's step"
    echo "   from an EL1 boot: efibootmgr --create --disk $DISK --part N --label $LABEL --loader '\\EFI\\book4\\grubaa64.efi'"
fi

echo "== done"
echo "Installed on $NEW (UUID $RUUID). Remove the stick and reboot."
