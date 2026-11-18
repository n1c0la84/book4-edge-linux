#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# 7.3 sleep hunt (18 November): the 7.3 kernel collapses CX with 7.2's EL2 DTB
# (97.1 %) and not with its own (0 %), so the blocker is in 7.3's device tree.
# This makes a copy of /boot/dtb-test/book4-73-el2.dtb with one group of nodes
# disabled, installs it next to it and adds the GRUB test entry "73-<group>".
#
#   bash tools/power/dt73-variant.sh nocs      coresight/QDSS nodes off (98.4 %, 18 Nov)
#   bash tools/power/dt73-variant.sh noctcu    only the CTCU (new in 7.3) off
#   bash tools/power/dt73-variant.sh noetr     CTCU, both ETRs and their replicators (all new in 7.3) off
#   bash tools/power/dt73-variant.sh noadc     PMIC ADC5 gen3 (sys-therm) off
#   bash tools/power/dt73-variant.sh nospss    SPSS GLINK transport off
#   bash tools/power/dt73-variant.sh remove GROUP   entry and file gone
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); repo=$(cd "$here/../.." && pwd)
group=${1:?group}; rel=7.3.4-book4
if [ "$group" = remove ]; then
    g=${2:?group}; bash "$repo/install/arch/test-entry.sh" remove "73-$g" || true
    b=$(mktemp -d); sudo mount /dev/sda4 "$b"; sudo rm -f "$b/dtb-test/book4-73-el2-$g.dtb"; sync; sudo umount "$b"; rmdir "$b"; exit 0
fi
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
b=$(mktemp -d); sudo mount /dev/sda4 "$b"; cp "$b/dtb-test/book4-73-el2.dtb" "$work/in.dtb"; sync; sudo umount "$b"; rmdir "$b"
python3 -I - "$group" "$work/in.dtb" "$work/out.dtb" <<'PY'
import sys, libfdt
group, src, dst = sys.argv[1:]
fdt = libfdt.Fdt(open(src, 'rb').read())
fdt.resize(fdt.totalsize() + 65536)
match = {
    'nocs':   lambda c, p: 'coresight' in c or 'qcom,coresight' in c or '/ctcu@' in p or '/tmc@' in p,
    'noctcu': lambda c, p: p == '/soc@0/ctcu@10001000',
    'noetr':  lambda c, p: p in ('/soc@0/ctcu@10001000', '/soc@0/tmc@10048000', '/soc@0/tmc@1004f000',
                                 '/soc@0/replicator@10046000', '/soc@0/replicator@1004e000'),
    'noadc':  lambda c, p: 'spmi-adc5-gen3' in c,
    'nospss': lambda c, p: not p.startswith('/reserved-memory') and ('spss' in c or 'spss' in p.split('/')[-1]),
}[group]
hits = []
def walk(off, path):
    try: comp = bytes(fdt.getprop(off, 'compatible')).decode('ascii', 'replace')
    except libfdt.FdtException: comp = ''
    if path != '/' and match(comp, path): hits.append(path)
    child = fdt.first_subnode(off, libfdt.QUIET_NOTFOUND)
    while child >= 0:
        walk(child, (path.rstrip('/') + '/' + fdt.get_name(child)))
        child = fdt.next_subnode(child, libfdt.QUIET_NOTFOUND)
walk(0, '/')
for p in hits:
    fdt.setprop_str(fdt.path_offset(p), 'status', 'disabled')
fdt.pack()
open(dst, 'wb').write(fdt.as_bytearray())
print(f"{len(hits)} node(s) disabled:"); [print('  ', p) for p in hits]
PY
b=$(mktemp -d); sudo mount /dev/sda4 "$b"; sudo install -m 644 "$work/out.dtb" "$b/dtb-test/book4-73-el2-$group.dtb"; sync; sudo umount "$b"; rmdir "$b"
bash "$repo/install/arch/test-entry.sh" remove "73-$group" >/dev/null 2>&1 || true
bash "$repo/install/arch/test-entry.sh" add "73-$group" kernel=/vmlinuz-$rel initrd=/initramfs-$rel-arch.img \
    dtb=/dtb-test/book4-73-el2-$group.dtb -clk_ignore_unused -pd_ignore_unused +id_aa64mmfr0.ecv=1
echo "Entry '... - test: 73-$group' added. Reboot, pick it, nap 2 min."
