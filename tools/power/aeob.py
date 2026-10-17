# SPDX-License-Identifier: GPL-2.0-only
"""Decode Qualcomm PEP 'AeoB' registry blobs: u16 type (0 int, 1 string,
3 package), u16 length, payload. usage: python3 -I aeob.py FILE [--json]"""
import struct, sys, json
def parse(b, o, end):
    out = []
    while o + 4 <= end:
        t, n = struct.unpack_from('<HH', b, o); o += 4
        if t == 0:
            v = int.from_bytes(b[o:o+n], 'little'); out.append(v)
        elif t == 1:
            out.append(b[o:o+n].rstrip(b'\0').decode('latin1'))
        elif t == 3:
            out.append(parse(b, o, o + n))
        else:
            out.append(f'?type{t}:{b[o:o+n].hex()}')
        o += n
    return out
d = open(sys.argv[1], 'rb').read()
blobs, o = [], 0
while o < len(d) and d[o:o+4] == b'AeoB':
    size = struct.unpack_from('<I', d, o + 4)[0]
    blobs.append(parse(d, o + 12, o + 8 + size)); o += 8 + size + (0)
    nxt = d.find(b'AeoB', o); o = nxt if nxt >= 0 else len(d)
print(json.dumps(blobs) if '--json' in sys.argv else blobs)
