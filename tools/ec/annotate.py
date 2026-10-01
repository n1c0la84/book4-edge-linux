#!/usr/bin/env python3
"""Annotate objdump output of EC2.sys: resolve adrp+add/ldr to strings and imports."""
import re, struct, subprocess, sys

PE = 'EC2.sys'
data = open(PE, 'rb').read()

# section table: name, vma, size, file offset
secs = []
for line in subprocess.run(['objdump', '-h', PE], capture_output=True, text=True).stdout.splitlines():
    m = re.match(r'\s*\d+\s+(\S+)\s+([0-9a-f]+)\s+([0-9a-f]+)\s+[0-9a-f]+\s+([0-9a-f]+)', line)
    if m:
        secs.append((m[1], int(m[3], 16), int(m[2], 16), int(m[4], 16)))

def off(va):
    for _, vma, size, fo in secs:
        if vma <= va < vma + size:
            return fo + va - vma
    return None

def cstr(va):
    o = off(va)
    if o is None:
        return None
    # UTF-16?
    if o + 3 < len(data) and data[o+1] == 0 and 32 <= data[o] < 127 and data[o+3] == 0:
        e = o
        while e + 1 < len(data) and data[e:e+2] != b'\0\0':
            e += 2
        s = data[o:e].decode('utf-16le', 'replace')
        return 'L"%s"' % s if len(s) >= 3 else None
    e = data.find(b'\0', o)
    s = data[o:e]
    if len(s) >= 3 and all(32 <= c < 127 or c in (9, 10, 13) for c in s):
        return '"%s"' % s.decode().replace('\n', '\\n')
    return None

# imports: IAT address -> name
imports = {}
dll = None
for line in subprocess.run(['objdump', '-p', PE], capture_output=True, text=True).stdout.splitlines():
    m = re.match(r'\s*DLL Name: (\S+)', line)
    if m:
        dll = m[1]
        continue
    m = re.match(r'\s+([0-9a-f]+)\s+(?:<none>\s+)?([0-9a-f]+)\s+(\S+)$', line)
    if dll and m and not m[3].isdigit():
        pass
# objdump -p lists "vma: Hint/Ord Member-Name Bound-To"; parse generically
text = subprocess.run(['objdump', '-p', PE], capture_output=True, text=True).stdout
for blk in re.split(r'\n\s*DLL Name: ', text)[1:]:
    name = blk.split('\n', 1)[0].strip()
    for m in re.finditer(r'\n\s+([0-9a-f]{4,})\s+([0-9a-f]+)\s+(\w+)', blk):
        imports[int(m[1], 16)] = '%s!%s' % (name, m[3])

# Build IAT slot -> name by walking import descriptors directly
imp_dir = None
for line in text.splitlines():
    m = re.match(r'Entry 1 ([0-9a-f]+) ([0-9a-f]+) Import Directory', line)
    if m:
        imp_dir = int(m[1], 16)
BASE = 0x140000000
iat = {}
if imp_dir:
    o = off(BASE + imp_dir)
    while True:
        ilt, _, _, name_rva, iat_rva = struct.unpack_from('<IIIII', data, o)
        if not name_rva:
            break
        dname = data[off(BASE+name_rva):].split(b'\0')[0].decode()
        i = 0
        while True:
            ent = struct.unpack_from('<Q', data, off(BASE + (ilt or iat_rva)) + 8*i)[0]
            if not ent:
                break
            if not ent >> 63:
                fn = data[off(BASE + (ent & 0x7fffffff)) + 2:].split(b'\0')[0].decode()
            else:
                fn = 'ord%d' % (ent & 0xffff)
            iat[BASE + iat_rva + 8*i] = '%s!%s' % (dname.split('.')[0], fn)
            i += 1
        o += 20

regs = {}
out = []
for line in open('EC2.dis'):
    line = line.rstrip('\n')
    note = ''
    m = re.match(r'\s*([0-9a-f]+):\s+[0-9a-f]{8}\s+(\w+)\s+(.*)', line)
    if m:
        op, args = m[2], m[3]
        a = [x.strip() for x in args.split(',')]
        if op == 'adrp':
            regs[a[0]] = int(re.search(r'0x([0-9a-f]+)', args)[1], 16)
        elif op == 'add' and len(a) >= 3 and a[1] in regs and a[2].startswith('#'):
            va = regs[a[1]] + int(a[2][1:], 0)
            s = cstr(va)
            note = s if s else ('&%s' % iat[va] if va in iat else '-> 0x%x' % va)
            regs[a[0]] = va
        elif op in ('ldr', 'str') and len(a) >= 2:
            mm = re.match(r'\[(\w+),#(0x[0-9a-f]+|\d+)\]', ','.join(a[1:]).replace(' ', ''))
            if mm and mm[1] in regs:
                va = regs[mm[1]] + int(mm[2], 0)
                note = iat.get(va, '[0x%x]' % va)
        handled = op == 'adrp' or (op == 'add' and note)
        writes = not (op.startswith(('st', 'b', 'cb', 'tb', 'cmp', 'cmn', 'tst', 'ret', 'nop', 'dmb', 'dsb', 'isb')))
        if writes and not handled and a and a[0] in regs:
            del regs[a[0]]
        if op in ('bl', 'blr', 'ret', 'b') or op.startswith('b.'):
            # calls clobber caller-saved regs; keep callee-saved x19-x28
            for r in list(regs):
                if not re.match(r'x(19|2[0-8])$', r):
                    del regs[r]
    out.append(line + (('\t; ' + note) if note else ''))
open('EC2.ann', 'w').write('\n'.join(out) + '\n')
print('imports:', len(iat), 'lines:', len(out))
