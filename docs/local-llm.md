# Local language models

`llama.cpp` on the CPU (12 Oryon cores, 16 GB RAM), as the Surface Pro 11
EL2 notes advise: CPU-only, because a build with the Vulkan backend makes
the CPU path about three times slower (weights in GPU-visible memory).

## Setup

    git clone --depth 1 https://github.com/ggml-org/llama.cpp ~/src/ext/llama.cpp
    cd ~/src/ext/llama.cpp
    uvx cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON \
        -DGGML_VULKAN=OFF -DGGML_OPENCL=OFF -DLLAMA_CURL=OFF -DLLAMA_BUILD_TESTS=OFF
    uvx cmake --build build -j 12 --target llama-cli llama-bench llama-server

(`uvx cmake`: a user-level cmake through uv, no package needed.) The build
detects `-mcpu=oryon-1+dotprod+i8mm`. On 23 October, commit `f5027fb`, it
took 1 min 1 s (10 min of CPU time) at **61-64 W from the battery**, about
1 Wh; idle is ~5 W.

Models go in `~/models/`.

## Results (23 October, EL2, sleep kernel 7.2.7-book4s without memlat)

Qwen3-8B, `Qwen3-8B-Q4_K_M.gguf` (5.0 GB, unsloth/Qwen3-8B-GGUF):

| threads | prompt (pp512) | generation (tg128) | power | energy per token |
|---|---|---|---|---|
| 4 | | 10.4 t/s | ~39 W | ~3.7 J |
| 6 | | 10.5 t/s | ~47 W | ~4.5 J |
| 8 | 75.8 t/s | 10.2 t/s | ~50 W | ~4.9 J |
| 12 | 85.1 t/s | 8.9 t/s | ~55-60 W | ~6.5 J |

Power from UPower's rate history (`GetHistory rate`), a sample every few
seconds, so approximate. Generation is memory-bound: 4 threads already
reach the limit, more only burn power (and 12 slow it down). Prompt
processing is compute-bound and uses all 12. So:

    ./build/bin/llama-cli -m ~/models/Qwen3-8B-Q4_K_M.gguf -t 4 -tb 12 -cnv

Qwen3-8B has a thinking and a direct mode in one model; `/no_think` or
`/think` in a message switches. The generation rate corresponds to about
53 GB/s of memory reads (5.0 GB per token x 10.5). The Surface Pro 11
measured 7 t/s for the same model without memlat (38 GB/s STREAM) and 21 t/s
with it; memlat is in the sleep kernel from the next build
(`tools/kernel/sleep-backport/0029-0036`).
