#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Fedora: build and install libfprint from libfprint MR !547 (SDCP v2,
# egismoc; unmerged upstream). The EgisTec 1c7a:05a1 only keeps enrolled
# prints over SDCP; with Fedora's libfprint 1.94.100 every verify finds 0
# prints on the chip and fprintd deletes the enrolment. The spec is Fedora's
# with the source swapped (userspace/fingerprint/libfprint-sdcp.spec); the
# version is locked so Fedora updates do not bring the broken one back.
#
#   bash install/fingerprint-libfprint.sh
#   undo: sudo dnf versionlock delete libfprint && sudo dnf distro-sync libfprint
# Run as your user. When MR !547 lands in a Fedora libfprint, undo instead.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
SPEC=$REPO/userspace/fingerprint/libfprint-sdcp.spec
W=${WORK:-$HOME/src/fp-rpm}
SHA=$(awk '/^%global mr_sha/{print $3}' "$SPEC")
mkdir -p "$W"
sudo -v
echo "== 1. build tools and dependencies"
sudo dnf install -y rpm-build
sudo dnf builddep -y "$SPEC"
echo "== 2. source (MR !547 at $SHA)"
TGZ=$W/libfprint-$SHA.tar.gz
[ -s "$TGZ" ] || curl -fL -o "$TGZ" \
    "https://gitlab.freedesktop.org/libfprint/libfprint/-/archive/$SHA/libfprint-$SHA.tar.gz"
echo "== 3. build (a few minutes; log in $W/build.log)"
rpmbuild -bb --define "_sourcedir $W" --define "_topdir $HOME/rpmbuild" "$SPEC" > "$W/build.log" 2>&1 ||
    { tail -40 "$W/build.log"; echo "build failed, full log: $W/build.log" >&2; exit 1; }
RPM=$(ls ~/rpmbuild/RPMS/aarch64/libfprint-*sdcp*.aarch64.rpm | grep -v -E 'devel|tests' | sort -V | tail -1)
echo "   $RPM"
echo "== 4. install and lock"
sudo dnf install -y "$RPM"
sudo dnf versionlock add libfprint
rpm -q libfprint
sudo systemctl restart fprintd
echo "Done. Enroll again (fprintd-enroll), then fprintd-verify; the print must"
echo "still be listed afterwards (fprintd-list $USER)."
