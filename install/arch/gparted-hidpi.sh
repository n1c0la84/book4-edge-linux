#!/usr/bin/env bash
# Give GTK applications launched as root the same readable text size as the
# 2x-scaled Book4 display.  In particular, pkexec deliberately drops
# GDK_SCALE, so GParted otherwise starts with its 11-point root GTK default.
set -euo pipefail

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

cat >"$tmpfile" <<'EOF'
[Settings]
# 11 pt is the normal GTK font here; root GUI applications do not inherit the
# user session's GDK_SCALE=2, so use the equivalent 22-point font instead.
gtk-font-name=Adwaita Sans 22
EOF

sudo install -d -m 0755 /root/.config/gtk-3.0
sudo install -m 0644 "$tmpfile" /root/.config/gtk-3.0/settings.ini

echo 'Installed the root GTK3 HiDPI font setting. Restart GParted to apply it.'
