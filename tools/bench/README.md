# CPU vs GPU vs NPU: one matrix multiply

`C = A * B` (n x n, float, row major) three ways, same inputs, best of N
runs, GFLOP/s, and the maximum error against the CPU result (relative to the
largest element of C). "total" includes copying A, B and C in and out of the
back end's buffers; "kernel" is the work alone (GFLOP/s is from kernel).

| back end | how | file |
|---|---|---|
| cpu | OpenMP over rows, i-k-j loop vectorised to NEON | `cpu.c` |
| gpu | Vulkan compute on the Adreno X1-85 (Mesa Turnip), 16x16 shared-memory tiles | `gpu.c`, `mm.comp` |
| npu | FastRPC call into the Hexagon v73 CDSP, HVX vectors in qf32, one thread | `npu/` |

## CPU and GPU

    make -C tools/bench
    tools/bench/bench -n 256,512,1024,2048 -r 10      # -b cpu,gpu to pick

25 October, EL2, on the charger (GFLOP/s, kernel time):

| n | cpu | gpu |
|---|---|---|
| 256 | 203 | 70 |
| 512 | 105 | 80 |
| 1024 | 136 | 86 |
| 2048 | 109 | 88 |

The GPU result matches the CPU's to ~5e-7. The shader computes one output per
thread and is far from the Adreno's peak (a few TFLOP/s fp32); register
blocking (4x4 outputs per thread) is the obvious next step.

## NPU

Needs the NPU setup from docs/TODO.md (Samsung's shells, `~/npu/rt`, the
`fastrpc` group) and the Hexagon SDK, which is x86 only:

    # on any x86 Docker host, also remote (sources and results go through tar):
    DOCKER_HOST=ssh://root@unraid bash tools/bench/npu/build-dsp.sh   # -> npu/out/
    make -C tools/bench NPU=1
    bash tools/bench/npu/install.sh            # libmm_skel.so next to the shells
    DSP_LIBRARY_PATH=~/npu/rt/share/qcom/x1e80100/dsp/cdsp \
        ~/src/ext/x1e-npu/scripts/safestep.sh /tmp/npu.log -- tools/bench/bench -b cpu,npu -n 256

It uses a plain FastRPC call per multiply, not llama.cpp's `dspqueue`, which
hangs on this firmware (qualcomm/fastrpc#377): whether this path works is
itself the first result. **After any hang, reboot before the next NPU run**
(a second session after a hung one crashed the CDSP, and at EL2 Linux cannot
restart it).

What the NPU number does not show: the "45 TOPS" are the HMX matrix engine at
int8, which has no public API (only QNN and llama.cpp's own kernels use it);
this measures the HVX vector units at fp32, single-threaded. Next steps:
4 HVX threads, fp16/int8 variants, power per back end.
