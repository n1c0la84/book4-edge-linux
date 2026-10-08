"""Disassemble an ARM64 PE driver and annotate string/import references.

usage: python disasm-pe.py DRIVER.sys OUT.asm  (needs capstone, pefile;
on Windows ARM64 use an x64 Python, capstone has no win-arm64 wheel)
"""
import re
import sys

import capstone
import pefile

pe = pefile.PE(sys.argv[1])
base = pe.OPTIONAL_HEADER.ImageBase
img = pe.get_memory_mapped_image()

imports = {}
for entry in getattr(pe, 'DIRECTORY_ENTRY_IMPORT', []):
    for imp in entry.imports:
        name = imp.name.decode() if imp.name else 'ord%d' % imp.ordinal
        imports[imp.address] = name


def string_at(va):
    off = va - base
    if off < 0 or off >= len(img):
        return None
    m = re.match(rb'([\x20-\x7e]{4,})\x00', img[off:off + 600])
    if m:
        return m.group(1).decode()
    m = re.match(rb'((?:[\x20-\x7e]\x00){3,})\x00\x00', img[off:off + 400])
    if m:
        return 'L"' + m.group(1).decode('utf-16le') + '"'
    return None


md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
out = open(sys.argv[2], 'w', encoding='utf-8')
for sec in pe.sections:
    if not sec.Characteristics & 0x20000000:  # executable
        continue
    start = base + sec.VirtualAddress
    code = img[sec.VirtualAddress:sec.VirtualAddress + sec.Misc_VirtualSize]
    regs = {}
    def walk():
        off = 0
        while off < len(code):
            n = 0
            for ins in md.disasm(code[off:], start + off):
                n += ins.size
                yield ins
            off += n
            if off < len(code):
                out.write('%x:\t.word\t0x%08x\n' % (start + off, int.from_bytes(code[off:off + 4], 'little')))
                off += 4
    for ins in walk():
        note = ''
        ops = ins.op_str
        if ins.mnemonic == 'adrp':
            r, v = ops.split(', ')
            regs[r] = int(v.lstrip('#'), 16)
        elif ins.mnemonic in ('add', 'ldr', 'ldrsw', 'str') and '#' in ops:
            m = re.match(r'(\w+), (?:\[)?(\w+), #(0x[0-9a-f]+|\d+)', ops)
            if m and m.group(2) in regs:
                va = regs[m.group(2)] + int(m.group(3), 0)
                if va in imports:
                    note = imports[va]
                else:
                    s = string_at(va)
                    note = repr(s) if s else 'data 0x%x' % va
                if ins.mnemonic == 'add':
                    regs[m.group(1)] = va
        dest = ops.split(',')[0].strip()
        if ins.mnemonic != 'adrp' and not (ins.mnemonic == 'add' and note) and dest in regs:
            del regs[dest]
        if ins.mnemonic in ('bl', 'b', 'ret', 'br', 'blr'):
            regs.clear()
        out.write('%x:\t%s\t%s%s\n' % (ins.address, ins.mnemonic, ops,
                                       ('\t; ' + note) if note else ''))
out.close()
