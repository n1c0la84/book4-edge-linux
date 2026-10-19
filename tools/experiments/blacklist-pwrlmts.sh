#!/usr/bin/env bash
# The Windows "Modern Standby" message (qcom_adsp_pwr_lmts, from x1e-sleep)
# crashes the Book4's ADSP at every suspend (19 Oct: EX:kernel:0x1:ipcc_irq121).
# Stop it auto-loading. Only the sleep test kernel 7.2.7-book4s has the module.
# Run as yourself: bash ~/blacklist-pwrlmts.sh
set -euo pipefail
printf '%s\n' '# book4-edge-linux: its Modern Standby message crashes the ADSP (docs/power.md, 19 Oct)' \
    'blacklist qcom_adsp_pwr_lmts' | sudo tee /etc/modprobe.d/book4-no-pwrlmts.conf >/dev/null
cat /etc/modprobe.d/book4-no-pwrlmts.conf
echo "Now reboot (F10 -> 'Book4 EL2 (slbounce)' -> 'test: el2-sleep'): the ADSP can't be restarted at EL2."
