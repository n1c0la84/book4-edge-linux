#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Runs inside the Arch Linux ARM container of .github/workflows/packages.yml:
# builds the named packages from this checkout (/w) as an unprivileged user
# without access to the signing key, checks build metadata, then signs them
# and updates the pacman repository in /w/out (the release's current files,
# downloaded by the workflow). book4-edge-firmware is never built here: it
# carries Windows/Qualcomm files and stays on the laptop.
#
#   build-packages.sh linux-book4 book4-edge book4-edge-boot book4-edge-el2 \
#       fastrpc libssc-book4 iio-sensor-proxy-book4 book4-sensors
#
# Environment: BOOK4_SIGN_KEY (armored secret key), BOOK4_SIGN_FPR.
set -euo pipefail
shopt -s nullglob
W=/w OUT=/w/out
[ $# -gt 0 ] || set -- linux-book4 book4-edge book4-edge-boot book4-edge-el2 \
    fastrpc libssc-book4 iio-sensor-proxy-book4 book4-sensors
for p; do
    case "$p" in linux-book4|book4-edge|book4-edge-boot|book4-edge-el2|fastrpc|libssc-book4|iio-sensor-proxy-book4|book4-sensors) ;;
    *) echo "refusing to build '$p' here" >&2; exit 1 ;; esac
done
[ -n "${BOOK4_SIGN_FPR:-}" ] || { echo "BOOK4_SIGN_FPR is empty" >&2; exit 1; }
[ -n "${BOOK4_SIGN_KEY:-}" ] || { echo "BOOK4_SIGN_KEY is empty" >&2; exit 1; }

SIGN_GNUPGHOME=$(mktemp -d /root/gnupg.XXXXXX)
chmod 700 "$SIGN_GNUPGHOME"
cleanup() {
    GNUPGHOME="$SIGN_GNUPGHOME" gpgconf --kill gpg-agent 2>/dev/null || true
    rm -rf "$SIGN_GNUPGHOME"
}
trap cleanup EXIT

echo "::group::system"
# no mount table, and no Landlock for pacman's download sandbox, in a container
sed -i -e 's/^CheckSpace/#CheckSpace/' -e '/^\[options\]/a DisableSandbox' /etc/pacman.conf
# the geo-redirecting default mirror stalls from GitHub's runners now and then
cat > /etc/pacman.d/mirrorlist <<'EOF2'
Server = http://fl.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://ca.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://de4.mirror.archlinuxarm.org/$arch/$repo
Server = http://dk.mirror.archlinuxarm.org/$arch/$repo
Server = http://mirror.archlinuxarm.org/$arch/$repo
EOF2
pacman-key --init >/dev/null
pacman-key --populate archlinuxarm >/dev/null
pacman -Syu --noconfirm --needed base-devel git gnupg bc cpio pahole python dtc kmod >/dev/null

# Import the signing key into a root-only keyring and scrub it from the
# environment before any package build runs as builder.
GNUPGHOME="$SIGN_GNUPGHOME" gpg --batch --import <<<"$BOOK4_SIGN_KEY" 2>/dev/null
unset BOOK4_SIGN_KEY
GNUPGHOME="$SIGN_GNUPGHOME" gpg --batch --list-secret-keys "$BOOK4_SIGN_FPR" >/dev/null

useradd -m builder
echo 'builder ALL=(ALL) NOPASSWD: /usr/bin/pacman' > /etc/sudoers.d/builder
cat >> /etc/makepkg.conf <<EOF
PACKAGER="Book4 Edge Linux CI"
MAKEFLAGS="-j$(nproc)"
EOF
git config --system --add safe.directory '*'
chown -R builder: "$W/packages"
chown -R root:root "$OUT"
echo "::endgroup::"

b() { env -u BOOK4_SIGN_KEY su -s /bin/bash builder -c "cd '$1' && $2"; }
built=()
for p; do
    echo "::group::$p"
    d=$W/packages/$p
    if [ "$p" = linux-book4 ]; then
        commit=$(sed -n 's/^_commit=\([0-9a-f]*\).*/\1/p' "$d/PKGBUILD")
        [ -n "$commit" ] || { echo "could not read _commit from $d/PKGBUILD" >&2; exit 1; }
        t=/home/builder/linux-book4
        b /home/builder "git init -q $t && git -C $t remote add origin https://github.com/n1c0la84/linux-book4-edge.git \
            && git -C $t fetch -q --depth 1 origin $commit && git -C $t checkout -q FETCH_HEAD"
        b "$d" "BOOK4_TREE=$t makepkg -s --noconfirm"
    elif [ "$p" = book4-sensors ]; then
        # nothing to compile; it depends on book4-edge-firmware, which is never
        # built here (each laptop builds it from its own Windows)
        b "$d" "makepkg -d --noconfirm"
    else
        # iio-sensor-proxy-book4 compiles against Arch's libssc (same API;
        # libssc-book4's patch only changes which data type it looks up)
        b "$d" "makepkg -s --noconfirm"
    fi
    pkg_count=0
    for f in "$d"/*.pkg.tar.*; do
        case "$f" in *.sig) continue ;; esac
        cp "$f" "$OUT/"
        built+=("$OUT/${f##*/}")
        pkg_count=$((pkg_count + 1))
    done
    [ "$pkg_count" -gt 0 ] || { echo "$p: no built packages found" >&2; exit 1; }
    echo "::endgroup::"
done

# The build machine must not show in what gets published. Package contents
# come from public sources (upstream code mentions other people's home paths,
# e.g. in kernel scripts and the BPF iterators skeleton), so check the
# metadata makepkg writes about the build: .BUILDINFO and .PKGINFO.
# Checked before signing or updating the repository database.
for f in "${built[@]}"; do
    h=$(bsdtar -xOf "$f" .BUILDINFO .PKGINFO 2>/dev/null | grep -oE '/home/[A-Za-z0-9_.-]+' | sort -u | grep -vx /home/builder || true)
    [ -z "$h" ] || { echo "${f##*/}: build metadata names $h" >&2; exit 1; }
done

echo "::group::repository"
for f in "${built[@]}"; do
    rm -f "$f.sig"
    GNUPGHOME="$SIGN_GNUPGHOME" gpg --batch --yes --detach-sign --use-agent --no-armor -u "$BOOK4_SIGN_FPR" "$f"
    GNUPGHOME="$SIGN_GNUPGHOME" gpg --batch --verify "$f.sig" "$f" 2>/dev/null
done
# -R drops each package's older file (and its signature) from out/
(cd "$OUT" && GNUPGHOME="$SIGN_GNUPGHOME" repo-add -q -R -s -k "$BOOK4_SIGN_FPR" book4.db.tar.gz "${built[@]##*/}")
# GitHub release assets cannot be symlinks: store the plain files under the names pacman asks for
for n in db files; do
    rm -f "$OUT/book4.$n" "$OUT/book4.$n.sig"
    cp "$OUT/book4.$n.tar.gz" "$OUT/book4.$n"
    cp "$OUT/book4.$n.tar.gz.sig" "$OUT/book4.$n.sig"
done
rm -f "$OUT"/*.old "$OUT"/*.old.sig
ls -l "$OUT"
echo "::endgroup::"
