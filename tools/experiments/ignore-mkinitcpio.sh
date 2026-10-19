#!/usr/bin/env bash
# Hold mkinitcpio at its current version: add it to IgnorePkg in /etc/pacman.conf.
# Run as yourself: bash ~/ignore-mkinitcpio.sh
set -euo pipefail

conf=/etc/pacman.conf

if grep -qE '^IgnorePkg.*\bmkinitcpio\b' "$conf"; then
  echo "mkinitcpio is already in IgnorePkg."
  exit 0
fi

sudo cp -p "$conf" "$conf.bak.$(date +%Y%m%d%H%M%S)"
sudo sed -i -E '0,/^IgnorePkg *=/s/^(IgnorePkg *=.*)$/\1 mkinitcpio/' "$conf"

grep -n '^IgnorePkg' "$conf"
