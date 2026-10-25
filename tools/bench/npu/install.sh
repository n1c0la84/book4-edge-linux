#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Put libmm_skel.so where the DSP fetches its libraries: next to Samsung's
# fastrpc shells (with DSP_LIBRARY_PATH set, libcdsprpc looks only there).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
dsp=${DSP_LIBRARY_PATH:-$HOME/npu/rt/share/qcom/x1e80100/dsp/cdsp}
[ -s "$here/out/libmm_skel.so" ] || { echo "no npu/out/libmm_skel.so: run build-dsp.sh first" >&2; exit 1; }
[ -e "$dsp/fastrpc_shell_unsigned_3" ] || { echo "no shells in $dsp (docs/TODO.md, NPU)" >&2; exit 1; }
install -m 644 "$here/out/libmm_skel.so" "$dsp/"
echo "installed $dsp/libmm_skel.so"
