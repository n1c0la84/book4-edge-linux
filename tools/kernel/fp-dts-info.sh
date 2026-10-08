#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Read-only: what enabling usb_2 (fingerprint reader, usb@a200000) involves.
# Prints the SoC nodes for usb_2 and its PHY from the kernel branch, how other
# X1E boards enable them, and whether our board touches them or TLMM 184.
# Run in Fedora or through install/arch/fedora-shell.sh, output to a file.
set -euo pipefail
export GIT_PAGER=cat
TREE=${TREE:-$HOME/src/patchwork}
REF=${REF:-book4/7.2}
D=arch/arm64/boot/dts/qcom
cd "$TREE"
show() { git show "$REF:$1"; }

echo "### SoC dtsi nodes (usb_2, usb_2_hsphy) in $REF"
for f in $(git ls-tree --name-only "$REF" $D/ | grep -E '/(hamoa|x1e80100|x1-common)[^/]*\.dtsi$'); do
    if show "$f" | grep -qE 'usb_2(_hsphy)?:'; then
        echo "== $f"
        show "$f" | grep -n -A40 -E '^\s*usb_2_hsphy: phy@|^\s*usb_2: usb@' | sed -n '1,120p'
    fi
done

echo
echo "### boards enabling &usb_2 / &usb_2_hsphy"
for f in $(git ls-tree --name-only "$REF" $D/ | grep -E '/x1[^/]*\.dtsi?$'); do
    if show "$f" | grep -qE '^&usb_2(_hsphy)? \{'; then
        echo "== $f"
        show "$f" | awk '/^&usb_2(_hsphy|_dwc3)? \{/,/^\};/'
        show "$f" | grep -n -B2 -A10 -E 'eusb[0-9]?_repeater|eusb2-repeater' | grep -B2 -A10 -iE 'usb_2|eusb[0-9]_repeater' | head -40
    fi
done

echo
echo "### our board: usb_2, TLMM 184, reserved ranges"
for f in $D/x1e80100-samsung-galaxy-book4-edge-14.dts $D/x1e-samsung-galaxy-book4-edge.dtsi; do
    echo "== $f"
    show "$f" | grep -n -E 'usb_2|gpio-reserved-ranges|\b184\b|repeater' || echo "   (nothing)"
done
