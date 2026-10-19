#!/usr/bin/env bash
# (Re-)add the GRUB test entry "drips-noflags": normal boot (EL1, Gunyah),
# DRIPS DTB, without clk_ignore_unused/pd_ignore_unused. Lists all entries.
# Then reboot (no slbounce stick), pick "test: drips-noflags", run:
#   bash ~/vreg-off-test.sh
# Run as yourself: bash ~/drips-noflags-readd.sh
set -euo pipefail
te=$HOME/Projects/book4-edge-linux/install/arch/test-entry.sh
bash ~/mount-ro.sh off >/dev/null 2>&1 || true
bash "$te" remove drips-noflags >/dev/null 2>&1 || true
bash "$te" add drips-noflags -clk_ignore_unused -pd_ignore_unused dtb=/dtb-test/book4-drips.dtb
bash "$te" list | grep -E '^menuentry' | sed -E 's/ --class.*//; s/ \{$//'
