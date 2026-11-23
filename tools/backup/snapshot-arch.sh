#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Read-only btrfs snapshot of the running Arch root subvolume (includes /home;
# arch-45 since the Omarchy 4.5 copy), taken at the top level of sda5.
# Run as yourself: bash tools/backup/snapshot-arch.sh [label]   (default label: pre-update)
#
# Roll back (from Fedora or a live system, with sda5's top level mounted at $top):
#   sudo mv $top/<subvol> $top/<subvol>-broken
#   sudo btrfs subvolume snapshot $top/<subvol>-<label>-<stamp> $top/<subvol>
# (<subvol> as in /etc/fstab and the GRUB entries, e.g. arch-45)
set -euo pipefail

uuid=4d74e1d5-7bca-48bf-a6e0-1362fd77882e
label=${1:-pre-update}
sub=$(findmnt -rn -o FSROOT /); sub=${sub#/}
[[ $(findmnt -rn -o UUID /) == "$uuid" && $sub == arch* && $sub != */* ]] \
  || { echo "error: / is not an Arch subvolume at the top level of sda5 ($sub); not touching anything." >&2; exit 1; }
name=$sub-$label-$(date +%Y%m%d-%H%M)

top=$(mktemp -d)
cleanup() { sudo umount "$top" 2>/dev/null || true; rmdir "$top"; }
trap cleanup EXIT

sudo mount -o subvolid=5 UUID=$uuid "$top"

[[ -d $top/$sub ]] || { echo "error: no $sub subvolume at the top level." >&2; exit 1; }
[[ ! -e $top/$name ]] || { echo "error: $name already exists." >&2; exit 1; }

sudo btrfs subvolume snapshot -r "$top/$sub" "$top/$name"

echo
echo "Snapshots at the top level of sda5:"
ls -1d "$top"/arch-* | xargs -n1 basename
echo
sudo btrfs filesystem usage -h "$top" | grep -E 'Free \(estimated\)'

nested=$(sudo btrfs subvolume list -o "$top/$sub" | awk '{print $NF}')
if [[ -n $nested ]]; then
  echo
  echo "note: nested subvolumes are NOT in the snapshot:"
  printf '  %s\n' $nested
fi
