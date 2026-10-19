#!/usr/bin/env bash
# Tidy the GRUB menu: remove every test entry (book4-extra.cfg on /boot)
# except the ones still in use, and show what else is in the menu.
# Keeps: pdc (7.3 PDC backport), drips-noflags (EL1 baseline), el2-drips,
# el2 (plain EL2, 48 h uptime test). Kernel images/DTBs in /boot stay.
# Run as yourself: bash ~/grub-cleanup.sh
set -euo pipefail
keep=" pdc drips-noflags el2-drips el2 "
te=$HOME/Projects/book4-edge-linux/install/arch/test-entry.sh
bash ~/mount-ro.sh off >/dev/null 2>&1 || true
sudo -v
names=$(bash "$te" list | sed -n 's/^# test-entry: //p')
for n in $names; do
  case "$keep" in *" $n "*) echo "keep    $n" ;; *) bash "$te" remove "$n" >/dev/null && echo "removed $n" ;; esac
done
echo
echo "== the GRUB menu now (generated entries, then test entries):"
esp=$(findmnt -rno TARGET -S /dev/sda1 | head -1 || true)
own=; [ -n "$esp" ] || { esp=$(mktemp -d); sudo mount -o ro /dev/sda1 "$esp"; own=1; }
sudo grep -E '^menuentry' "$esp/EFI/fedora/grub.cfg" | sed 's/^menuentry "\(.*\)" {$/  \1/'
[ -n "$own" ] && { sudo umount "$esp"; rmdir "$esp"; }
bash "$te" list | sed -n 's/^menuentry "\(.*\)" {$/  \1/p'
