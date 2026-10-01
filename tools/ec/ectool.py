#!/usr/bin/env python3
"""Samsung Galaxy Book4 Edge EC (ENE KB9058, ACPI SAM060B) test tool.

Protocol reverse-engineered from Windows EC2.sys (see NOTES.md):
  XDATA read : I2C write [30 00 HI LO] + repeated-start read 2 -> [50 VAL]
  XDATA write: I2C write [40 00 HI LO VAL]
  EC space   : mailbox in XDATA - FF10 cmd (0x88 read / 0x89 write, 0 = idle),
               F480 offset (read result comes back in F480), F481 write value,
               F49F slot bitmap, F49E collision bitmap.

  sudo python3 ectool.py probe        # stage 1: read-only XDATA reads, touches nothing
  sudo python3 ectool.py battery      # stage 2: EC-space reads of the ACPI ECR (0xA1) battery fields
  sudo python3 ectool.py dump         # stage 2: EC-space bytes 0x00-0xFF
"""
import ctypes, fcntl, glob, os, sys, time

ADDR = int(os.environ.get('BOOK4_EC_ADDR', '0x64'), 0)   # 0x64 mailbox on b80000; 0x62 events on b94000
BUS = os.environ.get('BOOK4_EC_BUS', 'b80000')
I2C_RDWR, I2C_M_RD = 0x0707, 0x0001

class Msg(ctypes.Structure):
    _fields_ = [('addr', ctypes.c_uint16), ('flags', ctypes.c_uint16),
                ('len', ctypes.c_uint16), ('buf', ctypes.POINTER(ctypes.c_uint8))]
class RdWr(ctypes.Structure):
    _fields_ = [('msgs', ctypes.POINTER(Msg)), ('nmsgs', ctypes.c_uint32)]

def find_bus():
    for d in glob.glob('/sys/bus/i2c/devices/i2c-*'):
        if os.path.realpath(d + '/..').endswith('/%s.i2c' % BUS):
            return '/dev/' + os.path.basename(d)
    sys.exit('%s I2C bus not found (is it enabled in the device tree?)' % BUS)

fd = os.open(find_bus(), os.O_RDWR)

def xfer(tx, rxlen=0):
    tb = (ctypes.c_uint8 * len(tx))(*tx)
    msgs = [Msg(ADDR, 0, len(tx), tb)]
    rb = (ctypes.c_uint8 * max(rxlen, 1))()
    if rxlen:
        msgs.append(Msg(ADDR, I2C_M_RD, rxlen, rb))
    arr = (Msg * len(msgs))(*msgs)
    fcntl.ioctl(fd, I2C_RDWR, RdWr(arr, len(msgs)))
    return list(rb[:rxlen])

def xread(a):
    r = xfer([0x30, 0x00, a >> 8, a & 0xff], 2)
    if r[0] != 0x50:
        raise IOError('XDATA %04x: bad status byte %02x (reply %s)' % (a, r[0], r))
    return r[1]

def xwrite(a, v):
    xfer([0x40, 0x00, a >> 8, a & 0xff, v])

def wait_idle():
    for _ in range(31):                       # Windows: up to 30 retries, 1 ms apart
        if xread(0xFF10) == 0:
            return
        time.sleep(0.001)
    raise IOError('mailbox busy (FF10 != 0)')

def get_slot():
    used, coll = xread(0xF49F), xread(0xF49E)
    if coll != used:
        xwrite(0xF49E, used)
    idx, mask = 0, 1
    while used & mask and idx < 8:
        mask <<= 1; idx += 1
    xwrite(0xF49F, used | mask)
    return idx

def slot_dirty(idx):
    return bool(xread(0xF49E) & (1 << idx))

def clear_slot(idx):
    m = ~(1 << idx) & 0xff
    xwrite(0xF49F, xread(0xF49F) & m)
    xwrite(0xF49E, xread(0xF49E) & m)

def ec_read(off):
    for _ in range(5):
        wait_idle()
        s = get_slot()
        xwrite(0xF480, off)
        xwrite(0xFF10, 0x88)
        wait_idle()
        v = xread(0xF480)
        dirty = slot_dirty(s)
        clear_slot(s)
        if not dirty:
            return v
    raise IOError('EC space %02x: collision on every retry' % off)

def u32(off):   # ACPI field = 4 consecutive EC-space bytes, little-endian
    return sum(ec_read(off + i) << (8 * i) for i in range(4))

def swap16(v):
    return ((v >> 8) | (v << 8)) & 0xffff

cmd = sys.argv[1] if len(sys.argv) > 1 else 'probe'
print('bus', find_bus(), 'addr 0x%02x' % ADDR)
if cmd == 'probe':
    for a in (0xFF10, 0xF49F, 0xF49E, 0xF480, 0xF481):
        r = xfer([0x30, 0x00, a >> 8, a & 0xff], 2)
        print('XDATA %04X -> %s %s' % (a, ' '.join('%02x' % b for b in r),
              'OK' if r[0] == 0x50 else '<- expected 50 first'))
elif cmd == 'battery':
    def s16(v): return v - 0x10000 if v & 0x8000 else v
    b80, st = ec_read(0x80), ec_read(0x84)
    rr, pv, af, vl = u32(0xA0), u32(0xA4), u32(0xB0), u32(0xB4)
    design, full = swap16(af & 0xffff), swap16(af >> 16)
    remain = swap16(rr >> 16)
    print('battery present  %d    AC online %d' % (b80 & 1, (b80 >> 2) & 1))
    print('state            %02x  (%s)' % (st, ', '.join(n for b, n in ((1, 'discharging'), (2, 'charging'), (4, 'critical')) if st & b) or 'idle'))
    print('remaining        %d mAh   (%.1f %% of last full)' % (remain, 100.0 * remain / full if full else 0))
    print('rate             %+d mA' % s16(swap16(pv & 0xffff)))
    print('voltage          %d mV' % swap16(pv >> 16))
    print('design capacity  %d mAh   <- must not change between runs' % design)
    print('last full        %d mAh' % full)
    print('design voltage   %d mV' % swap16(vl & 0xffff))
    print('raw: 80=%02x 84=%02x A0=%08x A4=%08x B0=%08x B4=%08x' % (b80, st, rr, pv, af, vl))
elif cmd == 'events':
    # EC2.sys's interrupt handler: plain 12-byte I2C read, no register address.
    # byte0 = type (1 hotkey, 4 fan trip, 6 OSD, 7 ACPI _Qxx event), byte1 = len, byte2.. = data.
    rb = (ctypes.c_uint8 * 12)()
    for i in range(int(sys.argv[2]) if len(sys.argv) > 2 else 16):
        m = (Msg * 1)(Msg(ADDR, I2C_M_RD, 12, rb))
        fcntl.ioctl(fd, I2C_RDWR, RdWr(m, 1))
        b = list(rb)
        print('event %2d: %s' % (i, ' '.join('%02x' % x for x in b)))
        if not any(b) or all(x == 0xff for x in b):
            print('queue empty')
            break
    if ADDR == 0x64:
        print('AC online now: %d' % ((ec_read(0x80) >> 2) & 1))
elif cmd == 'dump':
    for row in range(0, 0x100, 16):
        print('%02x: %s' % (row, ' '.join('%02x' % ec_read(row + i) for i in range(16))))
else:
    sys.exit(__doc__)
