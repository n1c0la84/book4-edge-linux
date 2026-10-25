// SPDX-License-Identifier: GPL-2.0-only
/*
 * NPU, CPU side: an unsigned FastRPC session on the CDSP (as llama.cpp
 * opens it) and one plain FastRPC call per multiply, not llama.cpp's
 * dspqueue (which hangs on CDSP.HT.2.9.c1-00078, qualcomm/fastrpc#377).
 * Buffers come from rpcmem (/dev/dma_heap/system), which FastRPC maps into
 * the DSP instead of copying; the copies here are from the harness's
 * malloc buffers into them, as for the GPU.
 *
 * Needs: the fastrpc group, libcdsprpc (~/npu/rt), libmm_skel.so next to
 * the shells in DSP_LIBRARY_PATH (npu/install.sh), and nothing hung on the
 * CDSP since boot (docs/TODO.md: reboot after a hung NPU run).
 */
#include <stdio.h>
#include <string.h>

#include "remote.h"
#include "rpcmem.h"

#include "../backend.h"
#include "mm.h"

static remote_handle64 h;
static float *bA, *bB, *bC;

static void npu_fini(void)
{
	if (bA) rpcmem_free(bA);
	if (bB) rpcmem_free(bB);
	if (bC) rpcmem_free(bC);
	bA = bB = bC = NULL;
	/* the session stays open across sizes; the process exit closes it */
}

static int npu_init(int n)
{
	size_t size = (size_t)n * n * sizeof(float);
	int err;

	if (!h) {
		struct remote_rpc_control_unsigned_module u = { .domain = CDSP_DOMAIN_ID, .enable = 1 };

		err = remote_session_control(DSPRPC_CONTROL_UNSIGNED_MODULE, &u, sizeof(u));
		if (err) {
			fprintf(stderr, "npu: unsigned PD request failed: 0x%08x\n", err);
			return -1;
		}
		err = mm_open(mm_URI CDSP_DOMAIN, &h);
		if (err) {
			fprintf(stderr, "npu: mm_open failed: 0x%08x (shells, libmm_skel.so, fastrpc group?)\n", err);
			h = 0;
			return -1;
		}
	}
	bA = rpcmem_alloc(RPCMEM_HEAP_ID_SYSTEM, RPCMEM_DEFAULT_FLAGS, size);
	bB = rpcmem_alloc(RPCMEM_HEAP_ID_SYSTEM, RPCMEM_DEFAULT_FLAGS, size);
	bC = rpcmem_alloc(RPCMEM_HEAP_ID_SYSTEM, RPCMEM_DEFAULT_FLAGS, size);
	if (!bA || !bB || !bC) {
		fprintf(stderr, "npu: rpcmem_alloc of %zu bytes failed\n", size);
		return -1;
	}
	return 0;
}

static int npu_run(const float *A, const float *B, float *C, int n, double *kernel_s)
{
	int len = n * n, err;

	memcpy(bA, A, len * sizeof(float));
	memcpy(bB, B, len * sizeof(float));
	double t0 = now();
	err = mm_run(h, bA, len, bB, len, bC, len, n);
	*kernel_s = now() - t0;
	if (err) {
		fprintf(stderr, "npu: mm_run failed: 0x%08x\n", err);
		return -1;
	}
	memcpy(C, bC, len * sizeof(float));
	return 0;
}

const struct backend backend_npu = { "npu", npu_init, npu_run, npu_fini };
