#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Give the Arch subvolume the fingerprint reader as on Fedora (the DTB is
# already shared): libfprint with SDCP (MR !547, built from
# userspace/fingerprint/arch/PKGBUILD as the Arch user, in a container),
# fprintd, the no-autosuspend udev rule, Fedora's enrolment record and
# fingerprint for sudo. The print lives on the sensor chip: Arch must reuse
# Fedora's record (a second enrolment of the same finger is refused as a
# duplicate), and fprintd-delete on either system removes it for both.
# Run as your user on Fedora, with Arch not running; needs the internet.
#
#   bash install/arch/sync-fingerprint.sh
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
TOP=/mnt/btrfs-top
R=$TOP/arch
DEV=/dev/sda5
AUSER=${ARCH_USER:-$USER}
ns() { sudo systemd-nspawn -q -D "$R" --resolv-conf=replace-uplink "$@"; }

[ -e /etc/fedora-release ] || { echo "Run this on Fedora." >&2; exit 1; }
FPREC=/var/lib/fprint/$USER
sudo test -d "$FPREC" || { echo "No enrolment on Fedora ($FPREC): fprintd-enroll there first." >&2; exit 1; }
sudo -v
echo "== 1. Arch subvolume"
sudo mkdir -p $TOP
mounted_here=0
if ! mountpoint -q $TOP; then
    sudo mount -o subvolid=5 $DEV $TOP
    mounted_here=1
fi
cleanup() { [ $mounted_here = 1 ] && sudo umount $TOP || true; }
trap cleanup EXIT
[ -e "$R/etc/mkinitcpio.conf.d/book4.conf" ] || { echo "$R does not look like our Arch install." >&2; exit 1; }
H=$R/home/$AUSER
[ -d "$H" ] || { echo "No $H in Arch (set ARCH_USER)." >&2; exit 1; }
own=$(sudo stat -c %u:%g "$H")

echo "== 2. build dependencies"
ns pacman -S --needed --noconfirm base-devel git meson glib2-devel gobject-introspection gtk-doc \
    python-cairo python-gobject openssl libgudev libgusb pixman

echo "== 3. build libfprint-sdcp as $AUSER (a few minutes)"
B=/home/$AUSER/.cache/book4-libfprint
sudo install -d -o "${own%:*}" -g "${own#*:}" "$R$B"
sudo install -m 644 -o "${own%:*}" -g "${own#*:}" "$REPO"/userspace/fingerprint/arch/PKGBUILD "$R$B/PKGBUILD"
ns runuser -u "$AUSER" -- bash -c "cd $B && makepkg -f --noconfirm" > /tmp/arch-libfprint-build.log 2>&1 ||
    { tail -30 /tmp/arch-libfprint-build.log; echo "build failed: /tmp/arch-libfprint-build.log" >&2; exit 1; }
PKG=$(sudo sh -c "ls -t $R$B/libfprint-sdcp-*.pkg.tar.zst" | grep -v debug | head -1)
echo "   ${PKG#$R}"

echo "== 4. install it (replacing Arch's libfprint) and fprintd"
PKGS=$(ns pacman -Qq)   # captured: grep -q in a pipe trips pipefail
grep -qx libfprint <<<"$PKGS" && ns pacman -Rdd --noconfirm libfprint
ns pacman -U --noconfirm "${PKG#$R}"
ns pacman -S --needed --noconfirm fprintd
ns pacman -Q libfprint-sdcp fprintd

echo "== 5. udev rule (no autosuspend)"
sudo install -m 644 "$REPO"/userspace/fingerprint/90-book4-fingerprint.rules "$R/etc/udev/rules.d/"

echo "== 6. enrolment record from Fedora (same print on the chip)"
sudo install -d -m 700 "$R/var/lib/fprint"
sudo cp -a "$FPREC" "$R/var/lib/fprint/$AUSER"
sudo find "$R/var/lib/fprint/$AUSER" -type f

echo "== 7. sudo by fingerprint"
P=$R/etc/pam.d/sudo
sudo grep -q pam_fprintd "$P" ||
    sudo sed -i '0,/^auth/s//auth       sufficient   pam_fprintd.so\n&/' "$P"
sudo cat "$P"

echo "== 8. lock screen PAM (shown, not changed)"
for f in hyprlock system-auth; do echo "-- /etc/pam.d/$f"; sudo cat "$R/etc/pam.d/$f" 2>/dev/null || echo "(none)"; done
echo
echo "Done. In Arch: sudo -k; sudo true   (rest the finger on the power button)"
