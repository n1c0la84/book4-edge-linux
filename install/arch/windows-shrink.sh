#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Shrink Windows (sda3, NTFS) and give the space to Arch's root filesystem,
# from the running system, without moving any partition:
#   1. checks: sda3 unmounted, charger online, ntfsresize dry run passes
#   2. ntfsresize sda3's NTFS to SIZE (asks you to confirm)
#   3. shrink partition 3 to the new size plus a 16 MiB margin (sfdisk keeps
#      its start, type and GUID, which Windows' boot configuration uses)
#   4. new partition 6 in the gap before /boot (sda4)
#   5. btrfs device add /dev/sda6 / (the root filesystem spans sda5 + sda6)
# A step that fails stops the script; every earlier state is consistent (an
# NTFS smaller than its partition is fine). Afterwards boot Windows once: it
# runs chkdsk (ntfsresize schedules it). Run as your user on Arch:
#
#   bash install/arch/windows-shrink.sh [SIZE_MB]     default 300000 (300 GB)
set -euo pipefail
DISK=/dev/sda WIN=/dev/sda3 BOOTP=/dev/sda4 NEW=/dev/sda6
mb=${1:-300000}
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
sec() { cat "/sys/class/block/${1#/dev/}/$2"; }

echo "== 1. checks"
findmnt -rn -S "$WIN" >/dev/null && { echo "error: $WIN is mounted" >&2; exit 1; }
[ ! -e "$NEW" ] || { echo "error: $NEW exists already" >&2; exit 1; }
grep -qx 1 /sys/class/power_supply/*/online 2>/dev/null || { echo "error: plug the charger in" >&2; exit 1; }
[ "$(lsblk -no FSTYPE "$WIN")" = ntfs ] || { echo "error: $WIN is not NTFS" >&2; exit 1; }
s3=$(sec $WIN start); n3=$(sec $WIN size); s4=$(sec $BOOTP start)
[ $((s3 + n3)) -eq "$s4" ] || { echo "error: sda3 does not end where sda4 starts" >&2; exit 1; }
bytes=$((mb * 1000000))
ntfs_sec=$(( (bytes + 511) / 512 ))
new3=$(( (ntfs_sec + 32768 + 2047) / 2048 * 2048 ))      # + 16 MiB, 1 MiB aligned
s6=$((s3 + new3)); n6=$((s4 - s6))
[ "$new3" -lt "$n3" ] && [ "$n6" -ge 2097152 ] || { echo "error: $mb MB leaves no room" >&2; exit 1; }
echo "   Windows: $((n3 * 512 / 1000000)) MB -> NTFS $mb MB, partition $((new3 * 512 / 1000000)) MB"
echo "   new $NEW: sectors $s6-$((s4 - 1)), $((n6 * 512 / 1000000)) MB for the root filesystem"
sudo -v
sudo ntfsresize --no-progress-bar -n -s "${mb}M" "$WIN" | tail -1 | grep -q 'ended successfully' ||
    { echo "error: the ntfsresize dry run failed; nothing changed" >&2; exit 1; }
echo "   dry run OK"
sudo sfdisk --dump "$DISK" > "$HOME/sda-table-before-shrink.sfdisk"
echo "   partition table saved: ~/sda-table-before-shrink.sfdisk (restore: sudo sfdisk $DISK < it)"

echo "== 2. NTFS -> $mb MB (answer y; takes a few minutes: ~43 GB to relocate)"
sudo ntfsresize --no-progress-bar -s "${mb}M" "$WIN"
sudo ntfsresize --info "$WIN" | grep -E 'Current volume size' | sed 's/^/   /'

echo "== 3. partition 3 -> $new3 sectors"
echo ",$new3" | sudo sfdisk --no-reread --no-tell-kernel -N 3 "$DISK" >/dev/null
echo "== 4. partition 6"
echo "$s6,$n6,L" | sudo sfdisk --no-reread --no-tell-kernel --append "$DISK" >/dev/null
sudo partx -u --nr 3 "$DISK"; sudo partx -a --nr 6 "$DISK"; sudo udevadm settle
[ "$(sec $WIN size)" -eq "$new3" ] && [ -e "$NEW" ] && [ "$(sec $NEW start)" -eq "$s6" ] ||
    { echo "error: the kernel does not see the new table yet; reboot, then: sudo btrfs device add $NEW /" >&2; exit 1; }
sudo ntfsresize --info "$WIN" >/dev/null 2>&1 && echo "   Windows NTFS readable after the change"
lsblk -o NAME,SIZE,FSTYPE "$DISK" | sed 's/^/   /'

echo "== 5. $NEW into the root filesystem"
sudo wipefs -q -a "$NEW"          # old NTFS free space; no signature may remain
sudo btrfs device add "$NEW" /
sudo btrfs filesystem show / | sed 's/^/   /'
df -h / | sed 's/^/   /'
echo; echo "Done. Boot Windows once soon: it checks the volume (chkdsk) on its first start."
