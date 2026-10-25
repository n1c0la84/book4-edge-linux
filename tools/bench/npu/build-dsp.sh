#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the NPU back end's Hexagon parts in Qualcomm's toolchain image (the
# one llama.cpp's Snapdragon build uses; amd64 only, contains the Hexagon
# SDK): qaic turns mm.idl into mm.h + mm_stub.c (CPU side, built later on
# the Book4 by make) + mm_skel.c, and hexagon-clang builds libmm_skel.so
# (DSP side) from mm_skel.c and dsp.c. Output: npu/out/.
#
# Sources go in and results come out through tar on stdin/stdout, so the
# Docker host can be remote, e.g. from the Book4:
#   DOCKER_HOST=ssh://root@unraid bash tools/bench/npu/build-dsp.sh
# or on any x86 machine with Docker and this repo:
#   bash tools/bench/npu/build-dsp.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
img=${IMG:-ghcr.io/snapdragon-toolchain/arm64-linux:v0.7}
out=$here/out
mkdir -p "$out"

tar -c -C "$here" mm.idl dsp.c |
docker run -i --rm --platform linux/amd64 "$img" bash -c '
set -euo pipefail
mkdir /tmp/w && cd /tmp/w && tar -x
SDK=${HEXAGON_SDK_ROOT:?HEXAGON_SDK_ROOT not set in the image}
TOOLS=${HEXAGON_TOOLS_ROOT:-$(dirname "$(dirname "$(find "$SDK" -path "*/Tools/bin/hexagon-clang" | head -1)")")}
QAIC=$(find "$SDK" -type f -name qaic -perm -u+x | head -1)
QURT=$SDK/rtos/qurt/computev73
[ -x "$QAIC" ] && [ -x "$TOOLS/bin/hexagon-clang" ] && [ -d "$QURT" ] || {
    echo "toolchain not found (SDK $SDK, tools $TOOLS, qaic $QAIC)" >&2; exit 1; }
mkdir out
"$QAIC" -mdll -I "$SDK/incs" -I "$SDK/incs/stddef" -o out mm.idl >&2
"$TOOLS/bin/hexagon-clang" -mv73 -mhvx -mhvx-length=128B -O2 -fPIC -G0 -shared \
    -I out -I "$SDK/incs" -I "$SDK/incs/stddef" \
    -I "$QURT/include" -I "$QURT/include/qurt" -I "$QURT/include/posix" \
    -o out/libmm_skel.so dsp.c out/mm_skel.c >&2
tar -c -C out mm.h mm_stub.c libmm_skel.so
' | tar -x -C "$out"
ls -l "$out"
echo "next, on the Book4: make -C tools/bench NPU=1 && bash tools/bench/npu/install.sh"
