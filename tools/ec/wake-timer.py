#!/usr/bin/env python3
"""Galaxy Book4 Edge EC wake timer test (EC raw channel, 0x62 on b94000).

From the Windows EC2.sys driver (decoded 8 October 2026, ec-protocol.md):
IOCTL_START_WAKEUP and IOCTL_START_WAKEUP_ONCE take one byte T (the driver
keeps only the low byte of a u32) and write {MODE, T / 60, T % 60}, MODE 2
(START) or 3 (ONCE); IOCTL_STOP_WAKEUP writes {0x04, 0x00}. All are plain
I2C writes on the raw target, like the keyboard backlight. The unit of T
(seconds or minutes) is not in the driver: this tool is for finding it out.

    sudo python3 wake-timer.py once T     # send {03, T/60, T%60}
    sudo python3 wake-timer.py start T    # send {02, T/60, T%60}
    sudo python3 wake-timer.py stop       # send {04, 00}
    sudo python3 wake-timer.py once T --sleep   # send, then s2idle at once

Test: `once 90 --sleep` with the lid open on battery, note the time, and
wait. A wake after ~90 s means seconds; nothing after 2-3 minutes, wait for
90 minutes (or wake it with the power key and try `once 2 --sleep`).
"""
import ctypes, fcntl, glob, os, sys, time

ADDR, BUS = 0x62, 'b94000'
I2C_RDWR = 0x0707

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

def write(fd, data):
    b = (ctypes.c_uint8 * len(data))(*data)
    fcntl.ioctl(fd, I2C_RDWR, RdWr((Msg * 1)(Msg(ADDR, 0, len(data), b)), 1))

args = [a for a in sys.argv[1:] if a != '--sleep']
if not args or args[0] not in ('once', 'start', 'stop'):
    sys.exit(__doc__)
if args[0] == 'stop':
    cmd = [0x04, 0x00]
else:
    t = int(args[1], 0) if len(args) > 1 else -1
    if not 0 <= t <= 255:
        sys.exit('T must be 0-255 (EC2.sys keeps one byte)')
    cmd = [0x03 if args[0] == 'once' else 0x02, t // 60, t % 60]
fd = os.open(bus(), os.O_RDWR)
write(fd, cmd)
print('%s  sent %s to 0x%02x on %s' % (time.strftime('%H:%M:%S'),
      ' '.join('%02x' % x for x in cmd), ADDR, bus()))
if '--sleep' in sys.argv:
    os.sync()
    t0 = time.time()
    with open('/sys/power/state', 'w') as f:
        f.write('mem')
    print('%s  resumed after %.0f s' % (time.strftime('%H:%M:%S'), time.time() - t0))
