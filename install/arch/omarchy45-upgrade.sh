#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Upgrade the test copy (install/arch/omarchy45-copy.sh) from the locally
# built Omarchy 4.0.4 to Omarchy's own packages from its aarch64 repository
# (4.5.0 on 16 November 2026). Refuses to run anywhere but in the copy.
# Review behind it: docs/TODO.md, "Omarchy 4.5 and Omarchy's own repository".
#
#   bash install/arch/omarchy45-upgrade.sh           steps 1-4
#   bash install/arch/omarchy45-upgrade.sh migrate   step 5, after a re-login
#   bash install/arch/omarchy45-upgrade.sh check     what state the copy is in
#
# 1. pacman.conf: Omarchy's mkinitcpio drop-ins added to NoExtract (4.5 has
#    three new ones; they would change our initramfs HOOKS), the [omarchy]
#    repository listed first (as Omarchy's own aarch64 pacman.conf does; the
#    Arch Linux ARM mirrors stay ours), and omarchy, omarchy-settings,
#    omarchy-keyring, mise-bin, google-chrome taken off IgnorePkg (mkinitcpio
#    stays held). Backup: /etc/pacman.conf.book4-pre45.
#    Hyprland and aquamarine: Omarchy's are older (0.56.2 / 0.15.1) than the
#    installed Arch ones; pacman keeps the newer installed ones.
# 2. pacman -Sy, then omarchy-keyring, omarchy, omarchy-settings from the
#    repository (pacman asks about replacing ttf-jetbrains-mono-nerd with
#    the -basic font: yes).
# 3. Checks: none of the NoExtract files arrived; the initramfs config still
#    has our HOOKS; the battery is still found (our 4.0.4 patch is not in the
#    stock package).
# 4. Lists the pending migrations.
# 5. migrate: runs omarchy-migrate (interactive). Migrations that install
#    apps from Omarchy's repository now work; the Limine/N1x ones skip
#    themselves here. Never run omarchy-reinstall-configs or
#    omarchy-refresh-limine (docs/STATE.md, hard rules).
set -euo pipefail
COPY=arch-45
cur=$(findmnt -rn -o FSROOT /); cur=${cur#/}
[ "$cur" = "$COPY" ] || { echo "error: this only runs in the test copy ($COPY); you are on '$cur'" >&2; exit 1; }
conf=/etc/pacman.conf

check() {
    echo "== state"
    echo "   subvolume: $cur; omarchy $(pacman -Q omarchy 2>/dev/null | cut -d' ' -f2), settings $(pacman -Q omarchy-settings 2>/dev/null | cut -d' ' -f2)"
    echo "   repositories: $(grep -E '^\[' $conf | grep -v options | tr '\n' ' ')"
    echo "   IgnorePkg: $(sed -n 's/^IgnorePkg *= *//p' $conf)"
    echo "   hyprland $(pacman -Q hyprland | cut -d' ' -f2), quickshell $(pacman -Q quickshell | cut -d' ' -f2)"
    bad=0
    for f in /etc/mkinitcpio.conf.d/00-omarchy-hooks.conf /etc/mkinitcpio.conf.d/omarchy_hooks.conf \
             /etc/mkinitcpio.conf.d/omarchy_vconsole.conf /etc/mkinitcpio.conf.d/i2c_hid_of_module.conf \
             /etc/mkinitcpio.conf.d/thunderbolt_module.conf /usr/share/libalpm/hooks/00-omarchy-update-guard.hook \
             /usr/share/omarchy/install/user/mise.sh; do
        [ ! -e "$f" ] || { echo "   PROBLEM: $f is installed (should be kept out by NoExtract)"; bad=1; }
    done
    ls /etc/limine-entry-tool.d/* >/dev/null 2>&1 && { echo "   PROBLEM: /etc/limine-entry-tool.d has files"; bad=1; } || true
    [ $bad = 1 ] || echo "   NoExtract files: none installed (good)"
    echo "   mkinitcpio drop-ins: $(ls /etc/mkinitcpio.conf.d/ | tr '\n' ' ')"
    if command -v omarchy-battery-present >/dev/null; then
        omarchy-battery-present >/dev/null 2>&1 && echo "   battery: found by omarchy-battery-present" ||
            echo "   battery: NOT found by omarchy-battery-present (our patch userspace/omarchy/patches/0001 is needed again)"
    fi
    if command -v omarchy-migrate >/dev/null; then
        echo "   pending migrations: $(omarchy-migrate --pending 2>/dev/null | wc -l)"
    fi
    hyprctl configerrors 2>/dev/null | head -5 | sed 's/^/   hyprland: /' || true
}

case "${1:-upgrade}" in
check) check; exit 0 ;;
migrate)
    echo "Running omarchy-migrate. Say no to anything that offers to reinstall configs or touch the boot loader."
    omarchy-migrate
    check; exit 0 ;;
upgrade) ;;
*) sed -n '3,12p' "$0"; exit 1 ;;
esac

sudo -v
echo "== 1. pacman.conf"
[ -e $conf.book4-pre45 ] || sudo cp -a $conf $conf.book4-pre45
tmp=$(mktemp)
awk '
  /^NoExtract *=/ && !/00-omarchy-hooks/ {
    $0 = $0 " etc/mkinitcpio.conf.d/00-omarchy-hooks.conf etc/mkinitcpio.conf.d/omarchy_vconsole.conf etc/mkinitcpio.conf.d/i2c_hid_of_module.conf"
  }
  /^IgnorePkg *=/ {
    n = split($0, w, /[ =]+/); out = "IgnorePkg ="
    for (i = 2; i <= n; i++) if (w[i] != "" && w[i] !~ /^(omarchy|omarchy-settings|omarchy-keyring|mise-bin|google-chrome)$/) out = out " " w[i]
    $0 = out
  }
  /^\[core\]/ && !done {
    print "# book4: Omarchy'"'"'s own repository, first, as in Omarchy'"'"'s aarch64 pacman.conf (16 November 2026)"
    print "[omarchy]"
    print "Server = https://pkgs.omarchy.org/stable/$arch"
    print ""
    done = 1
  }
  { print }
' $conf > "$tmp"
if grep -q '^\[omarchy\]' $conf; then echo "   [omarchy] already there, pacman.conf left as it is"
else
    grep -q '^\[omarchy\]' "$tmp" && grep -q 'mkinitcpio' <<<"$(sed -n 's/^IgnorePkg//p' "$tmp")" ||
        { echo "error: the edit of pacman.conf did not come out right; nothing changed" >&2; exit 1; }
    sudo install -m 644 "$tmp" $conf
    echo "   [omarchy] added first; IgnorePkg now:$(sed -n 's/^IgnorePkg *=//p' $conf)"
fi
rm -f "$tmp"

echo "== 2. packages"
sudo pacman -Sy
sudo pacman -S --needed omarchy-keyring
sudo pacman -S omarchy omarchy-settings

echo "== 3. checks"
check
echo
echo "== 4. next"
echo "Log out and in again (or reboot into this entry), look around, then:"
echo "  bash install/arch/omarchy45-upgrade.sh migrate"
echo "A full system update against the new repository (pacman -Syu) is a separate step: look at what it"
echo "would replace first with  pacman -Syu --print | less  (quickshell and yt-dlp move to Omarchy's builds)."
