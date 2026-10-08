#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Read-only: print one file from the kernel branch (default book4/7.2),
# for reading it from Arch. Run through install/arch/fedora-shell.sh:
#   fedora-shell.sh bash book4-edge-linux/tools/kernel/show-file.sh PATH > out.c
set -euo pipefail
TREE=${TREE:-$HOME/src/patchwork}
REF=${REF:-book4/7.2}
git -C "$TREE" --no-pager show "$REF:${1:?usage: $0 PATH}"
