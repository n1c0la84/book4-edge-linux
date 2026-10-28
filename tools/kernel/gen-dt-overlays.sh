#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# dts/src/*.dtso.in -> *.dtso: run the preprocessor with a kernel tree's
# dt-bindings, so the install scripts (build-sleep-kernel.sh,
# install/el2/sleep-dtb.sh) can apply plain overlays without kernel headers.
# Rerun after editing a .dtso.in and commit both files.
#
#   bash tools/kernel/gen-dt-overlays.sh [KERNEL_TREE]   (default ~/src/linux-book4-edge)
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
tree=${1:-$HOME/src/linux-book4-edge}
[ -d "$tree/include/dt-bindings" ] || { echo "error: $tree has no include/dt-bindings" >&2; exit 1; }
for in in "$repo"/dts/src/*.dtso.in; do
    out=${in%.in}
    {
        echo "// Generated from $(basename "$in") by tools/kernel/gen-dt-overlays.sh; edit that file instead."
        cpp -P -nostdinc -I "$tree/include" -I "$tree/scripts/dtc/include-prefixes" \
            -undef -D__DTS__ -x assembler-with-cpp "$in" | cat -s
    } > "$out"
    dtc -q -@ -I dts -O dtb -o /dev/null "$out"
    echo "$(basename "$out")"
done
