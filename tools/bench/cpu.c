// SPDX-License-Identifier: GPL-2.0-only
/* CPU: OpenMP over rows, i-k-j order so the inner loop vectorises to NEON. */
#include <string.h>

#include "backend.h"

static int cpu_init(int n)
{
	(void)n;
	return 0;
}

static int cpu_run(const float *A, const float *B, float *C, int n, double *kernel_s)
{
	double t0 = now();

	#pragma omp parallel for schedule(static)
	for (int i = 0; i < n; i++) {
		float *c = C + (size_t)i * n;

		memset(c, 0, n * sizeof(*c));
		for (int k = 0; k < n; k++) {
			const float a = A[(size_t)i * n + k];
			const float *b = B + (size_t)k * n;

			for (int j = 0; j < n; j++)
				c[j] += a * b[j];
		}
	}
	*kernel_s = now() - t0;
	return 0;
}

static void cpu_fini(void)
{
}

const struct backend backend_cpu = { "cpu", cpu_init, cpu_run, cpu_fini };
