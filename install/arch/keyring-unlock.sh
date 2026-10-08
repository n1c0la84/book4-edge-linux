#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Unlock the GNOME "login" keyring with the password typed at the SDDM login
# screen, as before Omarchy. Omarchy's install/login/sddm.sh removes the
# pam_gnome_keyring auth/password lines from /etc/pam.d/sddm (its model is a
# passwordless default keyring); the older, password-protected "login"
# keyring (Chrome Safe Storage, gh) then asks for its password in the
# session. This disk is not encrypted, so the keyring password is kept and
# PAM unlocks it instead.
#
#   bash install/arch/keyring-unlock.sh      (as your user on Arch)
#
# Idempotent; keeps /etc/pam.d/sddm.pre-keyring. Rerun after
# omarchy-apply-system (it removes the lines again). Undo: copy the backup
# back. Unlocking needs the login keyring's password to equal the account
# password; the password line keeps them in step on later password changes.
# Fingerprint or autologin at SDDM cannot unlock it (no password to pass on).
set -euo pipefail
F=/etc/pam.d/sddm
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
[ -e "$F" ] || { echo "No $F." >&2; exit 1; }

sudo -v
[ -e "$F.pre-keyring" ] || sudo cp -p "$F" "$F.pre-keyring"
if ! grep -qE '^-?auth\s+optional\s+pam_gnome_keyring\.so' "$F"; then
    # After the last auth line, like Arch's stock sddm file.
    last=$(grep -nE '^-?auth\b' "$F" | tail -1 | cut -d: -f1)
    sudo sed -i "${last}a -auth       optional    pam_gnome_keyring.so" "$F"
fi
if ! grep -qE '^-?password\s+optional\s+pam_gnome_keyring\.so' "$F"; then
    last=$(grep -nE '^-?password\b' "$F" | tail -1 | cut -d: -f1)
    sudo sed -i "${last}a -password   optional    pam_gnome_keyring.so" "$F"
fi
echo "== $F"
cat "$F"
echo
echo "Log out and back in at the SDDM screen with your password; apps should no longer ask for the keyring."
