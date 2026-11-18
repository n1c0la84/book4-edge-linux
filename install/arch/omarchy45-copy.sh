#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# A writable copy of the daily Arch system (btrfs snapshot of the `arch`
# subvolume, home included) with its own GRUB entry, to try the Omarchy 4.5
# upgrade without touching the daily system (docs/TODO.md, "Omarchy 4.5").
# The copy shares the data of the original and only grows as it changes.
# /boot and the ESP are shared: the copy boots the daily 7.3 kernel and DTB.
#
#   bash install/arch/omarchy45-copy.sh          create arch-45 and the entry "... - test: omarchy45"
#   bash install/arch/omarchy45-copy.sh undo     remove the entry and delete the copy (from the daily system)
#   bash install/arch/omarchy45-copy.sh adopt    print how to make the copy the daily system
#
# Then reboot normally (EL2 chain) and pick "... - test: omarchy45" in GRUB;
# on that boot run install/arch/omarchy45-upgrade.sh.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
DEV=/dev/disk/by-uuid/4d74e1d5-7bca-48bf-a6e0-1362fd77882e
SRC=arch; COPY=arch-45; name=omarchy45
cur=$(findmnt -rn -o FSROOT /); cur=${cur#/}
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }

top() { t=$(mktemp -d); sudo mount -o subvolid=5 "$DEV" "$t"; }
untop() { sudo umount "$t"; rmdir "$t"; }

case "${1:-create}" in
create)
    [ "$cur" = "$SRC" ] || { echo "error: run this from the daily system (subvolume $SRC), not from '$cur'" >&2; exit 1; }
    sudo -v; top
    if [ -e "$t/$COPY" ]; then untop; echo "error: $COPY already exists (undo first)" >&2; exit 1; fi
    sync
    sudo btrfs subvolume snapshot "$t/$SRC" "$t/$COPY"
    # the copy's fstab must mount the copy
    sudo sed -i "s|subvol=/$SRC |subvol=/$COPY |; s|subvol=/$SRC,|subvol=/$COPY,|; s|subvol=$SRC |subvol=$COPY |" "$t/$COPY/etc/fstab"
    grep -q "subvol=/\?$COPY" "$t/$COPY/etc/fstab" || { echo "error: could not point the copy's fstab at $COPY" >&2; sudo btrfs subvolume delete "$t/$COPY"; untop; exit 1; }
    echo "$COPY" | sudo tee "$t/$COPY/etc/book4-copy" >/dev/null
    untop
    # the daily EL2 entry with only the root subvolume changed
    bash "$here/test-entry.sh" remove $name >/dev/null 2>&1 || true
    bash "$here/test-entry.sh" add $name -rootflags "+rootflags=subvol=$COPY" +id_aa64mmfr0.ecv=1 \
        -clk_ignore_unused -pd_ignore_unused \
        kernel=/vmlinuz-7.3.4-book4 initrd=/initramfs-7.3.4-book4-arch.img dtb=/dtb-test/book4-73-el2.dtb
    echo
    echo "Created $COPY. Reboot, pick '... - test: $name' in GRUB, check with:"
    echo "  findmnt -no FSROOT /      (must print /$COPY)"
    echo "then run: bash install/arch/omarchy45-upgrade.sh"
    ;;
undo)
    [ "$cur" != "$COPY" ] || { echo "error: you are running from $COPY; boot the daily system first" >&2; exit 1; }
    sudo -v
    bash "$here/test-entry.sh" remove $name || true
    top
    [ ! -e "$t/$COPY" ] || sudo btrfs subvolume delete "$t/$COPY"
    untop
    echo "Removed $COPY and its entry."
    ;;
adopt)
    cat <<EOF
To make the copy the daily system once it is right (not automated, read first):
  1. Anything you changed in the daily system's home since the copy was made
     is NOT in the copy: move it over first (the daily root is mounted with
       sudo mount -o subvol=$SRC $DEV /mnt/old
     from the copy).
  2. From the copy: mount the top level (sudo mount -o subvolid=5 $DEV /mnt/top),
     rename the subvolumes:  mv /mnt/top/$SRC /mnt/top/arch-pre-45
                             mv /mnt/top/$COPY /mnt/top/$SRC
     and put subvol=/$SRC back in /mnt/top/$SRC/etc/fstab.
  3. Remove the test entry (bash install/arch/test-entry.sh remove $name) and reboot
     into the normal entry. Keep arch-pre-45 until you are sure, then delete it.
EOF
    ;;
*) sed -n '3,15p' "$0"; exit 1 ;;
esac
