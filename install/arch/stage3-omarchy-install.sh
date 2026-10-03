#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Arch stage 3b (after stage3-omarchy-build.sh): install Omarchy 4.0.4 on the
# Arch subvolume without its boot stack. Run as your user on Arch.
#
#   1. Read-only btrfs snapshot of the `arch` subvolume (rollback; /home included)
#   2. pacman.conf NoExtract: Omarchy's mkinitcpio hooks (would replace ours,
#      autodetect + plymouth + encrypt), its Limine drop-ins, the pacman guard
#      that blocks plain `pacman -Syu`, and install/user/mise.sh (it writes
#      mise stubs into ~/.local/bin, including one over a native `claude`)
#   3. omarchy-keyring, omarchy-settings, omarchy (local builds) + deps
#   4. Omarchy's default packages that exist in Arch Linux ARM (~410 with deps)
#   5. mise-bin from Omarchy's aarch64 repo (not in Arch Linux ARM)
#   6. omarchy-apply-system from a patched copy of its install tree. Skipped:
#      config/snapper.sh; post-install/pacman.sh, which replaces pacman.conf
#      and the mirrorlist with Omarchy's x86 ones; ufw-docker (not packaged)
#   7. Checks that nothing boot-related appeared
#
# Never touches /boot, the ESP, the kernel or the initramfs. Every step was
# run on 3 October 2026; step 5 and the mise.sh NoExtract were added
# afterwards (~/omarchy-mise.sh), so the script as a whole has not been run.
set -euo pipefail

if (( EUID == 0 )); then
  echo "Run as your user, not as root." >&2
  exit 1
fi
grep -q '^ID=archarm' /etc/os-release || grep -q '^NAME="Omarchy"' /etc/os-release ||
  { echo "Not on the Arch subvolume, stopping." >&2; exit 1; }

U=$(id -un)
BUILD=${OMARCHY_BUILD:-$HOME/src/omarchy-build}
AVAIL=$BUILD/avail.list
PKGS=(
  "$BUILD"/omarchy-keyring/omarchy-keyring-*-any.pkg.tar.*
  "$BUILD"/omarchy-settings/omarchy-settings-4.0.4-*-aarch64.pkg.tar.*
  "$BUILD"/omarchy/omarchy-4.0.4-*-aarch64.pkg.tar.*
)
MISE_PKG=https://pkgs.omarchy.org/stable/aarch64/mise-bin-2026.9.14-1-aarch64.pkg.tar.zst
NOEXTRACT="etc/mkinitcpio.conf.d/omarchy_hooks.conf etc/mkinitcpio.conf.d/thunderbolt_module.conf etc/limine-entry-tool.d/* usr/share/libalpm/hooks/00-omarchy-update-guard.hook usr/share/omarchy/install/user/mise.sh"
for f in "${PKGS[@]}" "$AVAIL"; do
  [[ -f $f ]] || { echo "Missing: $f (run stage3-omarchy-build.sh)" >&2; exit 1; }
done

sudo -v

echo "== 1. snapshot of the arch subvolume"
SNAP=arch-pre-omarchy-$(date +%Y%m%d-%H%M)
TOP=$(mktemp -d)
sudo mount -o subvolid=5 /dev/sda5 "$TOP"
sudo btrfs subvolume snapshot -r "$TOP/arch" "$TOP/$SNAP"
sudo umount "$TOP"; rmdir "$TOP"
echo "   snapshot: sda5 top level /$SNAP"

echo "== 2. pacman.conf NoExtract"
sudo cp -n /etc/pacman.conf /etc/pacman.conf.book4-pre-omarchy
if ! grep -q '^NoExtract.*omarchy_hooks' /etc/pacman.conf; then
  sudo sed -i "/^\[options\]/a # book4: keep Omarchy away from our initramfs and boot stack\nNoExtract = $NOEXTRACT" /etc/pacman.conf
fi
grep -n '^NoExtract' /etc/pacman.conf

echo "== 3. Omarchy packages"
sudo pacman -U --needed --noconfirm "${PKGS[@]}"

echo "== 4. Omarchy default packages available on Arch Linux ARM"
mapfile -t avail <"$AVAIL"
sudo pacman -S --needed --noconfirm "${avail[@]}"

echo "== 5. mise-bin from Omarchy's aarch64 repo (signature checked by pacman)"
sudo pacman -U --needed --noconfirm "$MISE_PKG"

echo "== 6. omarchy-apply-system (patched install tree)"
INST=/var/tmp/omarchy-install-book4
sudo rm -rf "$INST"
sudo cp -a /usr/share/omarchy/install "$INST"
echo 'echo "book4: skipped (no snapper/limine on this machine)"' | sudo tee "$INST/config/snapper.sh" >/dev/null
echo 'echo "book4: skipped (would replace the Arch Linux ARM pacman.conf and mirrorlist)"' | sudo tee "$INST/post-install/pacman.sh" >/dev/null
sudo tee "$INST/config/firewall.sh" >/dev/null <<'EOF'
# book4: Omarchy's firewall.sh without ufw-docker (not packaged for aarch64)
ufw default deny incoming
ufw default allow outgoing
ufw allow 53317/udp
ufw allow 53317/tcp
sed -i 's/^ENABLED=.*/ENABLED=yes/' /etc/ufw/ufw.conf
systemctl enable ufw
EOF
sudo env OMARCHY_INSTALL="$INST" OMARCHY_INSTALL_LOG_FILE=/var/log/omarchy-install.log \
  /usr/bin/omarchy-apply-system --install-user "$U" --first-install

echo "== 7. checks"
ls /etc/mkinitcpio.conf.d/ /etc/mkinitcpio.d/
ls /etc/limine-entry-tool.d/ 2>/dev/null || echo "   no /etc/limine-entry-tool.d (good)"
pacman -Q limine snapper grub 2>/dev/null || echo "   no limine/snapper/grub packages (good)"
ls /usr/share/omarchy/install/user/mise.sh 2>/dev/null || echo "   no install/user/mise.sh (good)"
grep -E '^\[|^Include' /etc/pacman.conf
pacman -Q omarchy omarchy-settings omarchy-keyring mise-bin
echo
echo "Done. Log: /var/log/omarchy-install.log   Rollback snapshot: /$SNAP on sda5"
echo "Next: stage3-omarchy-user.sh"
