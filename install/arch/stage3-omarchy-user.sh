#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Arch stage 3c (after stage3-omarchy-install.sh): move an existing user onto
# Omarchy's configs. Run as that user on Arch; no root needed.
#
# Do NOT use omarchy-reinstall-configs for this: after copying /etc/skel it
# runs omarchy-refresh-limine, which writes /boot/limine.conf and calls
# limine-update.
#
#   1. Backup of ~/.config, the bash dotfiles and ~/.local/share/applications
#   2. /etc/skel copied into $HOME (replaces ~/.config/hypr/*, ~/.bashrc).
#      /etc/skel also marks all shipped migrations as done, so `omarchy
#      update` will not replay old (Limine-era) ones
#   3. Monitor scale and keyboard layout in Omarchy's override files
#   4. omarchy-provision-user (theme, user dirs, default browser, keyring,
#      git identity), with the mise steps skipped
#
# Log out afterwards (Hyprland 0.56: hyprctl dispatch 'hl.dsp.exit()') and log
# in again from SDDM.
set -euo pipefail
SCALE=${ARCH_SCALE:-2}
KEYMAP=${ARCH_KEYMAP:-it}
NAME=${OMARCHY_USER_NAME:-$(git config --global user.name || true)}
EMAIL=${OMARCHY_USER_EMAIL:-$(git config --global user.email || true)}

if (( EUID == 0 )); then
  echo "Run as your user, not as root." >&2
  exit 1
fi
command -v omarchy-provision-user >/dev/null || { echo "Omarchy not installed (stage3-omarchy-install.sh)" >&2; exit 1; }

echo "== 1. backup"
B=$HOME/pre-omarchy-home-$(date +%Y%m%d-%H%M).tar.gz
(cd ~ && tar -czf "$B" --ignore-failed-read .config .bashrc .bash_profile .bash_logout .local/share/applications)
echo "   $B"

echo "== 2. Omarchy defaults from /etc/skel"
cp -af /etc/skel/. ~/

echo "== 3. scale $SCALE, keyboard $KEYMAP"
sed -i "s/^local omarchy_monitor_scale = \"auto\"/local omarchy_monitor_scale = $SCALE -- book4: 2880x1800 panel/" \
  ~/.config/hypr/monitors.lua
cat >>~/.config/hypr/input.lua <<EOF

-- book4: keyboard layout
hl.config({
  input = {
    kb_layout = "$KEYMAP",
  },
})
EOF
grep -n 'omarchy_monitor_scale =' ~/.config/hypr/monitors.lua

echo "== 4. omarchy-provision-user (mise steps skipped)"
INST=$(mktemp -d)
cp -a /usr/share/omarchy/install/. "$INST/"
echo 'echo "book4: skipped (mise stubs)"' >"$INST/user/mise.sh"
echo 'echo "book4: skipped (mise work dir)"' >"$INST/user/mise-work.sh"
OMARCHY_INSTALL=$INST OMARCHY_USER_NAME="$NAME" OMARCHY_USER_EMAIL="$EMAIL" \
  omarchy-provision-user --force
rm -rf "$INST"

echo
type -a claude 2>/dev/null || true
echo "Done. Log out and log in again from SDDM."
