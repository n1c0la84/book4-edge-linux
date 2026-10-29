#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Rebuild only samsung-emuec.ko for the daily kernel 7.2.7-book4s with our
# patches from drivers/anatase/patches/ (PD retry, quiesce across sleep, wake
# on plug-in, orientation), and install it (previous module kept as .prev).
# The counterpart of install/update-emuec-module.sh for the sleep kernel.
#
# Why (22 October): the book4s module had none of 0001-0003. Those were
# only ever installed into 7.2.7-book4 by update-emuec-module.sh (a patched
# copy, never committed to ~/src/patchwork), and the sleep kernel is built
# from a copy of that tree, so the unplug-during-sleep reset (Anatase #3)
# came back at EL2: charger out at 09:35, hard reset, RTC at 2024-05-29.
#
# The patches go into ~/src/patchwork-sleep's driver file itself, so later
# incremental builds of the sleep kernel keep them; build-sleep-kernel.sh
# applies them to a fresh copy as well. Run as your user on Arch:
#
#   bash tools/kernel/update-sleep-emuec.sh
#
# Rollback: sudo cp -p KO.prev KO; sudo depmod 7.2.7-book4s (paths printed).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
rel=7.2.7-book4s
ko=/usr/lib/modules/$rel/kernel/drivers/usb/typec/samsung-emuec.ko
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
[ -e "$ko" ] || { echo "error: no $ko; is $rel installed?" >&2; exit 1; }
if findmnt -rn -O ro /mnt/fedora/home >/dev/null; then
    echo "error: /mnt/fedora/home is mounted read-only; unmount it first" >&2; exit 1
fi
patches=$(tar -cz -C "$repo/drivers/anatase/patches" $(cd "$repo/drivers/anatase/patches" && ls *.patch) | base64 -w0)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

echo "== 1. patch ~/src/patchwork-sleep's samsung-emuec.c and build the module (Fedora container)"
inner="set -euo pipefail
cd ~/src/patchwork-sleep
[ \"\$(make -s LOCALVERSION=s kernelrelease)\" = $rel ]
p=\$(mktemp -d); echo $patches | base64 -d | tar -xz -C \$p
# Start from the tree's own (Anatase) file and apply the whole series: a
# reverse dry-run per patch cannot tell 'already applied' once later patches
# change its context (29 Oct: 0002 was re-applied over 0003/0004 and left
# half-applied).
git show HEAD:drivers/usb/typec/samsung-emuec.c > drivers/usb/typec/samsung-emuec.c
rm -f drivers/usb/typec/samsung-emuec.c.orig drivers/usb/typec/samsung-emuec.c.rej
for f in \$p/*.patch; do
    patch -s -p1 -d drivers/usb/typec -i \$f >&2 || { echo \"error: \$(basename \$f) does not apply\" >&2; exit 1; }
    echo \"   applied: \$(basename \$f)\" >&2
done
rm -f drivers/usb/typec/samsung-emuec.c.orig
grep -q 'pm: quiesced' drivers/usb/typec/samsung-emuec.c || { echo 'error: quiesce code still missing' >&2; exit 1; }
# external module against the configured tree (typec's exports, as in
# install/update-emuec-module.sh)
m=\$(mktemp -d); cp drivers/usb/typec/samsung-emuec.c \$m/
echo 'obj-m := samsung-emuec.o' > \$m/Makefile
make -s LOCALVERSION=s M=\$m modules >&2
cd \$m; tar -cz samsung-emuec.ko | base64 -w0"
systemd-inhibit --what=sleep:idle:handle-lid-switch --why="module build" \
    bash "$repo/install/arch/fedora-shell.sh" bash -lc "$inner" > "$work/ko.b64"
base64 -d "$work/ko.b64" | tar -xz -C "$work"
new=$work/samsung-emuec.ko
[ "$(modinfo -F vermagic "$new" | cut -d' ' -f1)" = $rel ] || { echo "error: vermagic is not $rel" >&2; exit 1; }
grep -qa 'pm: quiesced' "$new" || { echo "error: built module has no quiesce code" >&2; exit 1; }

echo "== 2. install (old module kept as .prev)"
sudo -v
sudo cp -p "$ko" "$ko.prev"
sudo install -m 644 "$new" "$ko"
sudo depmod $rel
echo "   $ko: $(modinfo -F vermagic "$ko" | cut -d' ' -f1), quiesce code present"
# Not in the initramfs today (typec is in no mkinitcpio hook); say so if
# that ever changes instead of rebuilding /boot from here.
img=$work/initramfs.img   # root-owned, but in our own directory: removable
sudo mkinitcpio -k $rel -g "$img" >/dev/null 2>&1
if sudo lsinitcpio "$img" | grep -q samsung-emuec; then
    echo "   NOTE: samsung-emuec is in the initramfs: rerun tools/kernel/build-sleep-kernel.sh to refresh /boot" >&2
else
    echo "   samsung-emuec is not in the initramfs (loaded from disk): nothing on /boot to update"
fi

echo
echo "Done; used from the next boot. Check after it: journalctl -k | grep 'pm: quiesced' at the first suspend."
echo "Rollback: sudo cp -p $ko.prev $ko; sudo depmod $rel"
