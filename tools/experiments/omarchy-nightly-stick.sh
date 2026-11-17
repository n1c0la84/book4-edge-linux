#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# The clean test of Omarchy's own image on the 14" (docs/ROADMAP.md):
# download Omarchy's nightly ARM installer image, check its checksum, and
# write it to a USB stick. Booting it changes nothing on the internal disk
# unless an install is started.
#
#   bash tools/experiments/omarchy-nightly-stick.sh fetch            download + verify (~8 GB, resumable)
#   bash tools/experiments/omarchy-nightly-stick.sh write /dev/sdX   write the verified image to that stick
#   bash tools/experiments/omarchy-nightly-stick.sh devices          list USB disks
#
# The image lands in ~/Downloads/omarchy-nightly/. It is Omarchy's, built
# nightly (https://nightly.omarchy.org/edge-aarch64/latest.json).
set -euo pipefail
dir=$HOME/Downloads/omarchy-nightly
meta=https://nightly.omarchy.org/edge-aarch64/latest.json

latest_iso() { ls -t "$dir"/omarchy-edge-*-aarch64.iso 2>/dev/null | head -1; }

fetch() {
    mkdir -p "$dir"; cd "$dir"
    curl -sfL -o latest.json "$meta"
    read -r url sum ver kernel < <(python3 -I -c 'import json,sys; d=json.load(open("latest.json")); print(d["url"], d["sha256"], d["version"], d["kernel"])')
    iso=$(basename "$url")
    echo "Omarchy nightly $ver, kernel $kernel: $iso"
    avail=$(df --output=avail -B1 "$dir" | tail -1)
    have=$(stat -c %s "$iso" 2>/dev/null || echo 0)
    size=$(python3 -I -c 'import json; print(json.load(open("latest.json"))["size"])')
    (( avail + have > size + 2*1024*1024*1024 )) || { echo "error: not enough free space for $(numfmt --to=iec "$size")" >&2; exit 1; }
    curl -fL -C - --progress-bar -o "$iso" "$url"
    echo "checking sha256..."
    echo "$sum  $iso" | sha256sum -c - || { echo "error: checksum mismatch; delete $dir/$iso and fetch again" >&2; exit 1; }
    echo "$ver $kernel" > "$iso.ok"
    echo "Verified: $dir/$iso"
    echo "Next: plug in a stick of 16 GB or more, then:  $0 devices  and  $0 write /dev/sdX"
}

devices() { lsblk -dpo NAME,SIZE,MODEL,TRAN,RM | awk 'NR==1 || $4=="usb"'; }

write() {
    local dev=${1:-} iso ok bytes root_disk p m
    iso=$(latest_iso)
    [ -n "$dev" ] || { echo "usage: $0 write /dev/sdX   (see: $0 devices)" >&2; exit 1; }
    [ -n "$iso" ] && [ -e "$iso.ok" ] || { echo "error: no verified image; run: $0 fetch" >&2; exit 1; }
    [ -b "$dev" ] && [ "$(lsblk -dno TYPE "$dev")" = disk ] || { echo "error: $dev is not a whole disk" >&2; exit 1; }
    root_disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE / | sed 's/\[.*//')")
    [ "$(basename "$dev")" != "$root_disk" ] || { echo "error: $dev holds the running system" >&2; exit 1; }
    [ "$(lsblk -dno TRAN "$dev")" = usb ] || { echo "error: $dev is not a USB disk" >&2; exit 1; }
    for p in $(lsblk -lnpo NAME "$dev"); do
        for m in $(findmnt -rn -o TARGET -S "$p"); do
            [[ $m == /run/media/* ]] && udisksctl unmount -b "$p" >/dev/null && echo "unmounted $p ($m)"
        done
    done
    ! lsblk -no MOUNTPOINTS "$dev" | grep -q . || { echo "error: $dev has mounted partitions" >&2; lsblk "$dev" >&2; exit 1; }
    bytes=$(stat -c %s "$iso")
    (( $(lsblk -bdno SIZE "$dev") >= bytes )) || { echo "error: $dev is smaller than the image" >&2; exit 1; }
    lsblk -o NAME,SIZE,MODEL,TRAN,LABEL "$dev"
    read -r -p "Write $(basename "$iso") to $dev ($(lsblk -dno SIZE "$dev") $(lsblk -dno MODEL "$dev")), erasing it? Type the device name ($dev): " ok
    [ "$ok" = "$dev" ] || { echo "Aborted."; exit 1; }
    sudo wipefs -qa "$dev"
    sudo dd if="$iso" of="$dev" bs=4M conv=fsync oflag=direct status=progress
    sudo udevadm settle
    echo "verifying..."
    sudo cmp -n "$bytes" "$iso" "$dev" || { echo "error: the stick differs from the image; write it again" >&2; exit 1; }
    echo "Done. Boot it: power off, F10 at power-on, pick the USB stick (docs/ROADMAP.md)."
}

case "${1:-}" in
fetch) fetch ;;
devices) devices ;;
write) write "${2:-}" ;;
*) sed -n '3,13p' "$0"; exit 1 ;;
esac
