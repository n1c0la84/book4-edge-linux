#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the two EFI programs of the EL2 boot chain (docs/el2.md) from pinned
# commits, natively on Arch (aarch64), with our patches:
#
#   qebspil  github.com/stephan-gh/qebspil 8e4d9e6
#            + qebspil-aoss-load-state.patch (justririll, x1e-sleep 4e84b60:
#              AOSS load_state before starting the DSPs; without it the ADSP
#              stops answering after the first DDR low-power mode)
#   slbounce github.com/TravMurav/slbounce c090a8c
#            + slbounce-tcblaunch-fallback.patch (also finds
#              \EFI\book4-el2\tcblaunch.exe)
#
# Output: $DEST/qebspil/out/qebspilaa64.efi and $DEST/slbounce/out/slbounce.efi
# (DEST defaults to ~/src/ext; existing checkouts are reused only if they are
# clean at the pinned commit). install/el2/esp-install.sh takes them from
# ~/src/ext (set QEBSPIL=/SLBOUNCE= there if DEST differs).
#
# Run as your user:  bash install/el2/build-efi.sh [DEST]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
dest=${1:-$HOME/src/ext}
mkdir -p "$dest"

fetch() {   # NAME URL COMMIT
    local d=$dest/$1
    if [ -d "$d/.git" ]; then
        [ "$(git -C "$d" rev-parse --short=7 HEAD)" = "$3" ] && [ -z "$(git -C "$d" status --porcelain --ignore-submodules)" ] ||
            { echo "error: $d exists but is not a clean checkout of $3; move it away or pass another DEST" >&2; exit 1; }
    else
        git clone -q "$2" "$d"
        git -C "$d" checkout -q "$3"
    fi
    git -C "$d" submodule update -q --init --recursive
}

undo() {    # back to the clean pinned tree (patch reverted), keeping out/
    git -C "$1" checkout -q -- .
    git -C "$1" clean -q -fd -e out -e external
}

echo "== qebspil"
fetch qebspil https://github.com/stephan-gh/qebspil.git 8e4d9e6
git -C "$dest/qebspil" apply "$here/qebspil-aoss-load-state.patch"
make -s -C "$dest/qebspil" CROSS_COMPILE= >/dev/null
undo "$dest/qebspil"
ls -l "$dest/qebspil/out/qebspilaa64.efi"

echo "== slbounce"
fetch slbounce https://github.com/TravMurav/slbounce.git c090a8c
git -C "$dest/slbounce" apply "$here/slbounce-tcblaunch-fallback.patch"
make -s -C "$dest/slbounce" CROSS_COMPILE= "$dest/slbounce/out/slbounce.efi" >/dev/null   # OUT_DIR is absolute
strings -el "$dest/slbounce/out/slbounce.efi" | grep -c book4-el2 >/dev/null ||
    { echo "error: slbounce.efi lacks the \\EFI\\book4-el2\\ fallback" >&2; exit 1; }
undo "$dest/slbounce"
ls -l "$dest/slbounce/out/slbounce.efi"
