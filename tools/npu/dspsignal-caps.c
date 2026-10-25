// SPDX-License-Identifier: GPL-2.0-only
/*
 * dspsignal support on the CDSP: attribute 130 (the DSP image) and 259 (the
 * kernel driver, sleep-backport 0041, probed by the patched libcdsprpc).
 * Both 1 = llama.cpp's dspqueue uses driver signaling. Safe: no queue, no
 * user PD.
 *   gcc -o dspsignal-caps dspsignal-caps.c -I ~/npu/rt/include/fastrpc \
 *       -L ~/npu/rt/lib -Wl,-rpath,$HOME/npu/rt/lib -lcdsprpc
 */
#include <stdio.h>

#include "remote.h"

int main(void)
{
	unsigned int ids[] = { 130 /* DSPSIGNAL_DSP_SUPPORT */, 259 /* DSPSIGNAL_DRIVER_SUPPORT */ };
	int ok = 1;

	for (int i = 0; i < 2; i++) {
		struct remote_dsp_capability c = { .domain = CDSP_DOMAIN_ID, .attribute_ID = ids[i] };
		int e = remote_handle_control(DSPRPC_GET_DSP_INFO, &c, sizeof(c));

		printf("attribute %u: err 0x%x capability %u\n", ids[i], e, c.capability);
		ok &= !e && c.capability == 1;
	}
	return ok ? 0 : 1;
}
