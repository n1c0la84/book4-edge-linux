#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Default: Fedora-container build. --local uses a prepared kernel tree.
# Builds an artifact only; does not install a kernel or load the module.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
case "${1:-}" in
    -h|--help)
        echo "Usage: bash $0 [--fedora [TREE] | --local TREE]"
        echo 'Default Fedora tree: ~/src/patchwork (inside Fedora)'
        exit 0 ;;
    --local) mode=local; tree=${2:?prepared kernel tree required} ;;
    --fedora|"") mode=fedora; tree=${2:-'~/src/patchwork'} ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if [[ $mode == local ]]; then
    cp "$here/psci_probe.c" "$here/Makefile" "$work/"
    make -C "$tree" LOCALVERSION= M="$work" W=1 modules
else
    if findmnt -rn -O ro /mnt/fedora/home >/dev/null; then
        echo "Fedora home is mounted read-only; unmount it before building." >&2
        exit 1
    fi
    # Paths are positional arguments, never interpolated as shell source.
    inner='set -euo pipefail
tree=$1
case "$tree" in "~/"*) tree="$HOME/${tree:2}" ;; esac
d=$(mktemp -d "$HOME/.psci-probe-build.XXXXXX")
trap '\''rm -rf "$d"'\'' EXIT
printf %s "$2" | base64 -d > "$d/psci_probe.c"
printf %s "$3" | base64 -d > "$d/Makefile"
make -s -C "$tree" LOCALVERSION= M="$d" W=1 modules >&2
base64 -w0 "$d/psci_probe.ko"'
    bash "$repo/install/arch/fedora-shell.sh" bash -c "$inner" _ "$tree" \
        "$(base64 -w0 "$here/psci_probe.c")" "$(base64 -w0 "$here/Makefile")" \
        > "$work/module.b64"
    base64 -d "$work/module.b64" > "$work/psci_probe.ko"
fi
vermagic=$(modinfo -F vermagic "$work/psci_probe.ko")
[[ ${vermagic%% *} == "$(uname -r)" ]] || {
    echo "Build kernel ${vermagic%% *} differs from running $(uname -r); not installing artifact." >&2
    exit 1
}
install -m 644 "$work/psci_probe.ko" "$here/psci_probe.ko"
printf 'Built %s (%s)\n' "$here/psci_probe.ko" "$vermagic"
