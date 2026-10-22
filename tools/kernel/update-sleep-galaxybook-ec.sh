#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Rebuild only samsung-galaxybook-ec.ko (battery, AC adapter, keyboard
# backlight) for the daily kernel 7.2.7-book4s with our patches from
# drivers/anatase/patches-galaxybook-ec/ (battery refreshed on read), and
# install it (previous module kept as .prev). The counterpart of
# install/update-galaxybook-ec-module.sh for the sleep kernel.
#
# Why (22 October): same story as tools/kernel/update-sleep-emuec.sh. 0001
# only ever reached 7.2.7-book4 as a module build, never ~/src/patchwork's
# source, so book4s has the original driver: charge, current and voltage
# frozen between plug events (9 % "Charging" at 374 mA for 16+ minutes).
#
# The patches go into ~/src/patchwork-sleep's driver file itself, so later
# incremental builds of the sleep kernel keep them; build-sleep-kernel.sh
# applies them to a fresh copy as well. Run as your user on Arch:
#
#   bash tools/kernel/update-sleep-galaxybook-ec.sh
#
# Rollback: sudo cp -p KO.prev KO; sudo depmod 7.2.7-book4s (paths printed).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
rel=7.2.7-book4s
ko=/usr/lib/modules/$rel/kernel/drivers/platform/arm64/samsung-galaxybook-ec.ko
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
[ -e "$ko" ] || { echo "error: no $ko; is $rel installed?" >&2; exit 1; }
if findmnt -rn -O ro /mnt/fedora/home >/dev/null; then
    echo "error: /mnt/fedora/home is mounted read-only; unmount it first" >&2; exit 1
fi
patches=$(tar -cz -C "$repo/drivers/anatase/patches-galaxybook-ec" $(cd "$repo/drivers/anatase/patches-galaxybook-ec" && ls *.patch) | base64 -w0)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

echo "== 1. patch ~/src/patchwork-sleep's samsung-galaxybook-ec.c and build the module (Fedora container)"
inner="set -euo pipefail
cd ~/src/patchwork-sleep
[ \"\$(make -s LOCALVERSION=s kernelrelease)\" = $rel ]
p=\$(mktemp -d); echo $patches | base64 -d | tar -xz -C \$p
for f in \$p/*.patch; do
    if patch -s -p1 -d drivers/platform/arm64 --dry-run -R -f -i \$f >/dev/null 2>&1; then
        echo \"   already in the tree: \$(basename \$f)\" >&2
    else
        patch -s -p1 -d drivers/platform/arm64 -f -i \$f >&2 || { echo \"error: \$(basename \$f) does not apply\" >&2; exit 1; }
        echo \"   applied: \$(basename \$f)\" >&2
    fi
done
rm -f drivers/platform/arm64/samsung-galaxybook-ec.c.orig
grep -q galaxybook_battery_update drivers/platform/arm64/samsung-galaxybook-ec.c || { echo 'error: refresh code still missing' >&2; exit 1; }
# external module against the configured tree (power_supply and
# platform_profile exports, as in install/update-galaxybook-ec-module.sh)
m=\$(mktemp -d); cp drivers/platform/arm64/samsung-galaxybook-ec.c \$m/
echo 'obj-m := samsung-galaxybook-ec.o' > \$m/Makefile
make -s LOCALVERSION=s M=\$m modules >&2
cd \$m; tar -cz samsung-galaxybook-ec.ko | base64 -w0"
systemd-inhibit --what=sleep:idle:handle-lid-switch --why="module build" \
    bash "$repo/install/arch/fedora-shell.sh" bash -lc "$inner" > "$work/ko.b64"
base64 -d "$work/ko.b64" | tar -xz -C "$work"
new=$work/samsung-galaxybook-ec.ko
[ "$(modinfo -F vermagic "$new" | cut -d' ' -f1)" = $rel ] || { echo "error: vermagic is not $rel" >&2; exit 1; }
grep -qa galaxybook_battery_update "$new" || { echo "error: built module has no refresh code" >&2; exit 1; }

echo "== 2. install (old module kept as .prev)"
sudo -v
sudo cp -p "$ko" "$ko.prev"
sudo install -m 644 "$new" "$ko"
sudo depmod $rel
echo "   $ko: $(modinfo -F vermagic "$ko" | cut -d' ' -f1), refresh code present"
# Not expected in the initramfs; say so if it is instead of rebuilding /boot
# from here.
img=$work/initramfs.img   # root-owned, but in our own directory: removable
sudo mkinitcpio -k $rel -g "$img" >/dev/null 2>&1
if sudo lsinitcpio "$img" | grep -q samsung-galaxybook-ec; then
    echo "   NOTE: samsung-galaxybook-ec is in the initramfs: rerun tools/kernel/build-sleep-kernel.sh to refresh /boot" >&2
else
    echo "   samsung-galaxybook-ec is not in the initramfs (loaded from disk): nothing on /boot to update"
fi

echo
echo "Done; used from the next boot (or now: sudo modprobe -r samsung-galaxybook-ec && sudo modprobe samsung-galaxybook-ec)."
echo "Check: cat /sys/class/power_supply/samsung-galaxybook-battery/current_now changes from one read to the next."
echo "Rollback: sudo cp -p $ko.prev $ko; sudo depmod $rel"
