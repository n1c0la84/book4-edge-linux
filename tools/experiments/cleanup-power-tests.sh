#!/usr/bin/env bash
# Remove the 14-15 October suspend-drain test material (the tools are in the
# repo now). Shows each item before deleting it.
#   /boot: the test GRUB entries (book4-extra.cfg), dtb-test/qce-active.dtb,
#          initramfs-7.2.7-book4-arch-ufstest.img
#   Fedora home: ~/src/patchwork-qce (reflink copy of the kernel tree),
#                ~/src/qce-modules, ~/src/icc-hold
# Run as yourself on Arch: bash ~/cleanup-power-tests.sh
set -euo pipefail
repo=$HOME/Projects/book4-edge-linux
uuid=4d74e1d5-7bca-48bf-a6e0-1362fd77882e
if findmnt -rn /mnt/fedora/home >/dev/null || findmnt -rn -S /dev/sda4 >/dev/null || findmnt -rn -S /dev/sda1 >/dev/null; then
  bash ~/mount-ro.sh off
fi
sudo -v

echo "== GRUB test entries:"
bash "$repo/install/arch/test-entry.sh" list
bash "$repo/install/arch/test-entry.sh" clear

b=$(mktemp -d); sudo mount /dev/sda4 "$b"
for f in dtb-test/qce-active.dtb initramfs-7.2.7-book4-arch-ufstest.img; do
  if [ -e "$b/$f" ]; then ls -la "$b/$f"; sudo rm "$b/$f"; echo "   removed /boot/$f"; fi
done
sync; sudo umount "$b"; rmdir "$b"

h=$(mktemp -d); sudo mount -o subvol=home UUID=$uuid "$h"
for d in nicola/src/patchwork-qce nicola/src/qce-modules nicola/src/icc-hold; do
  if [ -e "$h/$d" ]; then
    echo "   $d: $(sudo du -sh --apparent-size "$h/$d" | cut -f1) (apparent; reflinked data is shared)"
    sudo rm -rf --one-file-system "$h/$d"; echo "   removed Fedora ~/${d#nicola/}"
  fi
done
[ -e "$h/nicola/src/patchwork/.config" ] && echo "== the real kernel tree ~/src/patchwork is untouched"
sync; sudo umount "$h"; rmdir "$h"
echo "== done"
