#!/usr/bin/env python3
"""Read-only: raw S2MM006 status bytes 0x0E-0x14 of a USB-C port controller.

samsung-emuec derives the plug orientation from CC_STATUS (0x11) bits 7:4
(1 = normal, 2 = reverse) and reads "reverse" for both plug orientations
(8 Oct 2026). This prints the raw bytes so the two orientations can be
compared. Plain reads with the driver's framing (2-byte register address,
then a read), no writes; 0x15+ (latched events) are not touched.

    sudo python3 pdic-cc.py [BUS] [watch]   # BUS 1 = port0 (1-0033), 3 = port1
"""
import ctypes, fcntl, sys, time

BUS = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 1
ADDR, I2C_RDWR, I2C_M_RD = 0x33, 0x0707, 0x0001
REGS = range(0x0e, 0x15)

class Msg(ctypes.Structure):
    _fields_ = [('addr', ctypes.c_uint16), ('flags', ctypes.c_uint16),
                ('len', ctypes.c_uint16), ('buf', ctypes.POINTER(ctypes.c_uint8))]
class RdWr(ctypes.Structure):
    _fields_ = [('msgs', ctypes.POINTER(Msg)), ('nmsgs', ctypes.c_uint32)]

fd = open('/dev/i2c-%d' % BUS, 'rb+', buffering=0)

def read(reg):
    a = (ctypes.c_uint8 * 2)(reg >> 8, reg & 0xff)
    b = (ctypes.c_uint8 * 1)()
    m = (Msg * 2)(Msg(ADDR, 0, 2, a), Msg(ADDR, I2C_M_RD, 1, b))
    fcntl.ioctl(fd, I2C_RDWR, RdWr(m, 2))
    return b[0]

def line():
    v = {r: read(r) for r in REGS}
    orient = open('/sys/class/typec/port%d/orientation' % (0 if BUS == 1 else 1)).read().strip()
    return '%s  %s  | cc=0x%02x bin %s  sysfs=%s' % (
        time.strftime('%T'), ' '.join('%02x:%02x' % (r, v[r]) for r in REGS),
        v[0x11], format(v[0x11], '08b'), orient)

if 'watch' in sys.argv:
    last = None
    for _ in range(60):
        l = line()
        if l.split('  ', 1)[1] != last:
            print(l, flush=True)
            last = l.split('  ', 1)[1]
        time.sleep(1)
else:
    print(line())
