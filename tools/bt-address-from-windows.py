#!/usr/bin/env python3
"""Print the Bluetooth adapter address Windows uses on this machine.

Reads SYSTEM\\ControlSet001\\Services\\BTHPORT\\Parameters\\Keys from the
Windows registry hive; each subkey there is named after a local adapter.

    sudo mount -o ro /dev/sdXN /mnt/win
    tools/bt-address-from-windows.py /mnt/win
"""
import struct
import sys

def main(root):
    d = open(f'{root}/Windows/System32/config/SYSTEM', 'rb').read()
    base = 0x1000

    def cell(off):
        return base + off + 4

    def nk(off):
        o = cell(off)
        if d[o:o + 2] != b'nk':
            raise ValueError('not a key node')
        nsub, = struct.unpack_from('<I', d, o + 0x14)
        lst, = struct.unpack_from('<I', d, o + 0x1c)
        nlen, = struct.unpack_from('<H', d, o + 0x48)
        flags, = struct.unpack_from('<H', d, o + 2)
        enc = 'latin1' if flags & 0x20 else 'utf-16le'
        return d[o + 0x4c:o + 0x4c + nlen].decode(enc, 'replace'), nsub, lst

    def subkeys(off):
        _, n, lst = nk(off)
        out = []
        if not n or lst == 0xffffffff:
            return out

        def walk(l):
            o = cell(l)
            sig = d[o:o + 2]
            cnt, = struct.unpack_from('<H', d, o + 2)
            if sig in (b'lf', b'lh'):
                out.extend(struct.unpack_from('<I', d, o + 4 + 8 * i)[0] for i in range(cnt))
            elif sig == b'li':
                out.extend(struct.unpack_from('<I', d, o + 4 + 4 * i)[0] for i in range(cnt))
            elif sig == b'ri':
                for i in range(cnt):
                    walk(struct.unpack_from('<I', d, o + 4 + 4 * i)[0])
        walk(lst)
        return out

    key, = struct.unpack_from('<I', d, 0x24)
    for part in ('ControlSet001', 'Services', 'BTHPORT', 'Parameters', 'Keys'):
        key = next((s for s in subkeys(key) if nk(s)[0].lower() == part.lower()), None)
        if key is None:
            sys.exit(f'registry path not found at {part}')
    for adapter in subkeys(key):
        name = nk(adapter)[0]
        print(':'.join(name[i:i + 2] for i in range(0, 12, 2)).upper())

if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
