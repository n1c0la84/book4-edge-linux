/* SPDX-License-Identifier: GPL-2.0-only */
/* One matrix multiply C = A * B (n x n, row major, float), three back ends. */
#ifndef BENCH_BACKEND_H
#define BENCH_BACKEND_H

struct backend {
	const char *name;
	/* Once per size: allocate buffers, open devices. 0 = ok. */
	int (*init)(int n);
	/* C = A * B. *kernel_s gets the time without copies in and out
	 * (the same as the whole call where nothing is copied). 0 = ok. */
	int (*run)(const float *A, const float *B, float *C, int n, double *kernel_s);
	void (*fini)(void);
};

extern const struct backend backend_cpu;
extern const struct backend backend_gpu;
#ifdef BENCH_NPU
extern const struct backend backend_npu;
#endif

double now(void);

#endif
