#!/usr/bin/env python3
"""Galaxy Book4 Edge keyboard backlight test (EC raw channel, 0x62 on b94000).

From the Windows EC2.sys driver: IOCTL_SET_KBDBLT takes (timeout, level) and
queues the 3-byte command {0x10, timeout, level}, which its worker sends as a
plain I2C write on the EC's "raw" target (ACPI ECTC: 0x62 on \\_SB.I2C6, the
b94000 bus). IOCTL_GET_KBDBLT queues {0x11}.

    sudo python3 kbd-backlight.py probe            # does 0x62 answer? (plain read, like EC2.sys)
    sudo python3 kbd-backlight.py LEVEL [TIMEOUT]  # send {0x10, TIMEOUT, LEVEL}; TIMEOUT defaults to 0
"""
import ctypes, fcntl, glob, os, sys

ADDR, BUS = 0x62, 'b94000'
I2C_RDWR, I2C_M_RD = 0x0707, 0x0001

class Msg(ctypes.Structure):
    _fields_ = [('addr', ctypes.c_uint16), ('flags', ctypes.c_uint16),
                ('len', ctypes.c_uint16), ('buf', ctypes.POINTER(ctypes.c_uint8))]
class RdWr(ctypes.Structure):
    _fields_ = [('msgs', ctypes.POINTER(Msg)), ('nmsgs', ctypes.c_uint32)]

def bus():
    for d in glob.glob('/sys/bus/i2c/devices/i2c-*'):
        if os.path.realpath(d + '/..').endswith('/%s.i2c' % BUS):
            return '/dev/' + os.path.basename(d)
    sys.exit('%s I2C bus not found - booted with the Anatase device tree?' % BUS)

def xfer(fd, data=None, rlen=0):
    if data is not None:
        b = (ctypes.c_uint8 * len(data))(*data); m = Msg(ADDR, 0, len(data), b)
    else:
        b = (ctypes.c_uint8 * rlen)(); m = Msg(ADDR, I2C_M_RD, rlen, b)
    fcntl.ioctl(fd, I2C_RDWR, RdWr((Msg * 1)(m), 1))
    return list(b)

if len(sys.argv) < 2:
    sys.exit(__doc__)
fd = os.open(bus(), os.O_RDWR)
print('bus', bus(), 'addr 0x%02x' % ADDR)
if sys.argv[1] == 'probe':
    try:
        print('read 12:', ' '.join('%02x' % x for x in xfer(fd, rlen=12)))
    except OSError as e:
        sys.exit('no answer at 0x%02x: %s' % (ADDR, e))
else:
    level = int(sys.argv[1], 0)
    timeout = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0
    if not (0 <= level <= 255 and 0 <= timeout <= 255):
        sys.exit('values must be 0-255')
    xfer(fd, [0x10, timeout, level])
    print('sent 10 %02x %02x  (timeout %d, level %d)' % (timeout, level, timeout, level))
