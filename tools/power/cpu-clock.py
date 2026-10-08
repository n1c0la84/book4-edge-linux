#!/usr/bin/env python3
"""Measure the real CPU clock on ARM64 (Linux or Windows), without counters.

Runs a chain of 100 dependent `add x0, x0, #1` (one cycle each) in a loop,
so instructions per second = clock. Each worker is pinned to one CPU.

    python3 cpu-clock.py              # one worker on CPU 0, then 4, then 8
    python3 cpu-clock.py all          # one worker per CPU, all at once
    python3 cpu-clock.py 0 5 11       # one worker on each listed CPU, in turn

Linux cross-check: with scmi-cpufreq loaded the busy cores run at
3417.6 MHz (power.md), so this should print ~3418 there.
"""
import ctypes, mmap, multiprocessing as mp, os, sys, time

N = 100                                   # adds per loop iteration
code = [0xAA0003E1,                       # mov x1, x0   (iterations)
        0xD2800000]                       # mov x0, #0
code += [0x91000400] * N                  # add x0, x0, #1
code += [0xF1000421,                      # subs x1, x1, #1
         0x54000001 | (((-(N + 1)) & 0x7FFFF) << 5),   # b.ne loop
         0xD65F03C0]                      # ret
CODE = b''.join(c.to_bytes(4, 'little') for c in code)


def make_func():
    if os.name == 'nt':
        k32 = ctypes.windll.kernel32
        k32.VirtualAlloc.restype = ctypes.c_void_p
        k32.VirtualAlloc.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_ulong, ctypes.c_ulong]
        addr = k32.VirtualAlloc(None, len(CODE), 0x3000, 0x40)   # MEM_COMMIT|RESERVE, RWX
        ctypes.memmove(addr, CODE, len(CODE))
        k32.FlushInstructionCache(ctypes.c_void_p(-1), ctypes.c_void_p(addr), len(CODE))
    else:
        m = mmap.mmap(-1, mmap.PAGESIZE, prot=mmap.PROT_READ | mmap.PROT_WRITE | mmap.PROT_EXEC)
        m.write(CODE)
        addr = ctypes.addressof(ctypes.c_char.from_buffer(m))
        make_func.keep = m
    return ctypes.CFUNCTYPE(ctypes.c_uint64, ctypes.c_uint64)(addr)


def pin(cpu):
    if os.name == 'nt':
        ctypes.windll.kernel32.SetThreadAffinityMask(ctypes.windll.kernel32.GetCurrentThread(), 1 << cpu)
    else:
        os.sched_setaffinity(0, {cpu})


def worker(cpu, seconds=5.0):
    pin(cpu)
    f = make_func()
    f(1000000)                            # warm up, let the governor ramp
    best, end = 0.0, time.perf_counter() + seconds
    while time.perf_counter() < end:
        t = time.perf_counter()
        f(2000000)
        best = max(best, 2000000 * (N + 2) / (time.perf_counter() - t) / 1e6)
    return cpu, best


if __name__ == '__main__':
    ncpu = os.cpu_count()
    if sys.argv[1:] == ['all']:
        with mp.Pool(ncpu) as p:
            res = p.map(worker, range(ncpu))
        print('all %d at once: ' % ncpu + ', '.join('cpu%d %.0f' % r for r in res) + ' MHz')
    else:
        for cpu in [int(a) for a in sys.argv[1:]] or [0, 4, 8]:
            print('cpu%d alone: %.0f MHz' % worker(cpu))
