// SPDX-License-Identifier: GPL-2.0-only
/*
 * NPU, DSP side: C = A * B on the Hexagon v73 HVX vector units, 32 floats
 * per 128-byte vector, accumulated in qf32 (HVX's internal float format)
 * and converted back to IEEE float at the end. One hardware thread for
 * now; HMX (the matrix engine behind the "45 TOPS") has no public API.
 * Built by build-dsp.sh with the Hexagon SDK.
 */
#include <stdlib.h>

#include "AEEStdErr.h"
#include "HAP_farf.h"
#include "HAP_power.h"
#include "hexagon_types.h"
#include "hvx_hexagon_protos.h"
#include "qurt.h"

#include "mm.h"

int mm_open(const char *uri, remote_handle64 *h)
{
	HAP_power_request_t req = { 0 };
	void *ctx = malloc(1);

	(void)uri;
	if (!ctx)
		return AEE_ENOMEMORY;
	/* HVX must be powered before the first vector instruction */
	req.type = HAP_power_set_HVX;
	req.hvx.power_up = TRUE;
	HAP_power_set(ctx, &req);
	*h = (remote_handle64)ctx;
	return AEE_SUCCESS;
}

int mm_close(remote_handle64 h)
{
	HAP_power_request_t req = { 0 };

	req.type = HAP_power_set_HVX;
	req.hvx.power_up = FALSE;
	HAP_power_set((void *)h, &req);
	free((void *)h);
	return AEE_SUCCESS;
}

int mm_run(remote_handle64 h, const float *A, int la, const float *B, int lb, float *C, int lc, int n)
{
	(void)h;
	if (n <= 0 || n % 32 || la != n * n || lb != n * n || lc != n * n)
		return AEE_EBADPARM;
	/* rpcmem buffers are page aligned and n % 32 == 0: every row of B
	 * and C starts on a 128-byte boundary */
	if (((size_t)B | (size_t)C) & 127)
		return AEE_EBADPARM;
	if (qurt_hvx_lock(QURT_HVX_MODE_128B) != QURT_EOK)
		return AEE_ERESOURCENOTFOUND;

	for (int i = 0; i < n; i++) {
		for (int j = 0; j < n; j += 32) {
			HVX_Vector acc = Q6_V_vzero();

			for (int k = 0; k < n; k++) {
				float a = A[i * n + k];
				HVX_Vector va = Q6_V_vsplat_R(*(int *)&a);
				HVX_Vector vb = *(const HVX_Vector *)&B[k * n + j];

				acc = Q6_Vqf32_vadd_Vqf32Vqf32(acc, Q6_Vqf32_vmpy_VsfVsf(va, vb));
			}
			*(HVX_Vector *)&C[i * n + j] = Q6_Vsf_equals_Vqf32(acc);
		}
	}

	qurt_hvx_unlock();
	return AEE_SUCCESS;
}
