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

    ./build/bin/llama-cli -m ~/models/Qwen3-8B-Q4_K_M.gguf -t 4 -tb 12 -cnv   # before memlat; see below

Qwen3-8B has a thinking and a direct mode in one model; `/no_think` or
`/think` in a message switches. The generation rate corresponds to about
53 GB/s of memory reads (5.0 GB per token x 10.5). The Surface Pro 11
measured 7 t/s for the same model without memlat (38 GB/s STREAM) and 21 t/s
with it; memlat is in the sleep kernel from the next build
(`tools/kernel/sleep-backport/0029-0036`).

## CPU baseline: Geekbench 7 (23 October)

Geekbench 7.1.0 Linux/AArch64 preview (official, `cdn.geekbench.com`,
`Geekbench-7.1.0-LinuxARMPreview.tar.gz`; run from its folder, `--cpu`; the
preview uploads every result publicly): **single-core 2202, multi-core
13226** at EL2 on 7.2.7-book4s without memlat, on battery, max 3.42 GHz (the
4.0 GHz boost is never requested on Linux). Geekbench 7 is calibrated to 2500
= Ryzen 7 7700. The X1E-80-100's browser average was reported as 2261 / 14483
(not checked directly: the browser refuses scripted requests): about -3 %
single-core and -9 % multi-core here, the multi-core gap plausibly memory
bandwidth. To repeat after the memlat build.

## With memlat and boost (23 October, evening)

Sleep kernel with sleep-backport 0029-0037 (memlat; schedutil reaching the
4.0 GHz boost), on the charger. Boost: `tools/power/cpu-clock.py` reads
4003 MHz on CPU 4, 3996/4000 on CPUs 8/9 (one single 704 MHz reading on CPU
8 right after CPU 4 had boosted, not reproduced), 3410 on CPU 0 (no boost
step). memlat: DDR 547 MHz idle, ~2.1 GHz during generation (up to 4224),
LLCC 300 -> 806-1066 MHz.

Qwen3-8B Q4_K_M:

| threads | generation before | generation now | prompt now |
|---|---|---|---|
| 4 | 10.4 t/s | **16.2 t/s** | |
| 6 | 10.5 | **19.4** | 63.7 t/s |
| 8 | 10.2 | **20.9** | |
| 12 | 8.9 | 12.8 | 80.9 t/s |

The Surface Pro 11 measured 21.4 t/s with memlat. Prompt processing is
compute-bound and unchanged (all-core work does not boost). Best now:

    ./build/bin/llama-cli -m ~/models/Qwen3-8B-Q4_K_M.gguf -t 8 -tb 12 -cnv

Geekbench 7 on the same kernel, on the charger: **single-core 2200,
multi-core 16352** (was 2202 / 13226): multi-core +24 % from memlat, now
above the X1E-80-100 browser average. Single-core did not move although
clusters 1 and 2 ran at 4.0 GHz for ~450 s of the run: every CPU reports
`cpu_capacity` 1024, so the scheduler does not prefer the boosting clusters
and the single-core thread also ran on cluster 0 (3.42 GHz max, no boost
step). Pinned to the boosting clusters (`taskset -c 4-11`): **single-core
2482** (+13 %; multi-core 13302 on those 8 cores only). So the kernel should
rate clusters 1 and 2 above cluster 0 (capacity from the boost frequency:
0037 sets `capacity_freq_ref`, but the capacities are not rescaled).

## opencode with the local model (23 October)

A user service runs the server on demand (`~/.config/systemd/user/llama-server.service`):

    llama-server -m ~/models/Qwen3-8B-Q4_K_M.gguf -a qwen3-8b --host 127.0.0.1 --port 8080 \
        -t 8 -tb 12 -c 32768 -fa on -ctk q8_0 -ctv q8_0 -np 1 -cram 2048 --jinja --cache-reuse 256

32k context because opencode's system prompt and tool list alone are ~10k
tokens; the q8_0 KV cache keeps the whole server at ~7 GB. The same port
serves the chat page at http://127.0.0.1:8080. opencode (Omarchy's,
through mise) gets a provider in `~/.config/opencode/opencode.json`:

    "provider": { "llama.cpp": {
        "npm": "@ai-sdk/openai-compatible", "name": "llama.cpp (local)",
        "options": { "baseURL": "http://127.0.0.1:8080/v1" },
        "models": { "qwen3-8b": { "name": "Qwen3-8B (local)", "tool_call": true,
                                  "limit": { "context": 32768, "output": 8192 } } } } }

Use: `systemctl --user start llama-server`, then `opencode -m llama.cpp/qwen3-8b`;
`systemctl --user stop llama-server` frees the RAM. The first request reads
opencode's whole prompt at ~80 t/s (two minutes or so); llama-server keeps it
cached, so later turns only pay for what is new.

A lean agent for it (`agent.lean` in `opencode.json`, prompt in
`~/.config/opencode/prompts/lean.md`, ten lines): the default "build" agent
sends ~11.4k tokens (three minutes at ~65 t/s) because it describes twelve
tools, among them `skill` (which lists every skill under `~/.claude/skills`),
`task` and `webfetch`. "lean" keeps read, grep, glob, edit, write and bash
(the rest set to "deny" under `permission`), runs on `llama.cpp/qwen3-8b` at
Qwen3's recommended temperature 0.6 / top_p 0.95. Tab switches to it in
opencode, or `opencode --agent lean`. `opencode debug agent lean` shows
what it resolves to.

`-np 1` (one request at a time): with the default slots, opencode's
session-title request ran beside the first real one, and both crawled
(lean agent, 23 October: 3,457-token prompt at 19 t/s, output at 3 t/s,
the title at 0.6 t/s; 3 min 34 s to the first reply). Queued, the
title takes seconds and the prompt ~45 s. `-cram 2048` caps the RAM prompt
cache that keeps the main prompt while the title request has the slot
(default 8 GB).
