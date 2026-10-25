// SPDX-License-Identifier: GPL-2.0-only
/*
 * The same matrix multiply on the CPU, the GPU (Vulkan) and the NPU
 * (Hexagon CDSP over FastRPC): best of N runs, GFLOP/s, error against the
 * CPU result.
 *
 *   ./bench [-n 256,512,1024] [-r 10] [-b cpu,gpu,npu]
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "backend.h"

double now(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec * 1e-9;
}

static const struct backend *backends[] = {
	&backend_cpu,
	&backend_gpu,
#ifdef BENCH_NPU
	&backend_npu,
#endif
};

static int wanted(const char *list, const char *name)
{
	char buf[256], *tok, *save;

	if (!list)
		return 1;
	snprintf(buf, sizeof(buf), "%s", list);
	for (tok = strtok_r(buf, ",", &save); tok; tok = strtok_r(NULL, ",", &save))
		if (!strcmp(tok, name))
			return 1;
	return 0;
}

int main(int argc, char **argv)
{
	const char *sizes = "256,512,1024,2048", *only = NULL;
	int reps = 10, opt;

	while ((opt = getopt(argc, argv, "n:r:b:")) != -1) {
		switch (opt) {
		case 'n': sizes = optarg; break;
		case 'r': reps = atoi(optarg); break;
		case 'b': only = optarg; break;
		default:
			fprintf(stderr, "usage: %s [-n 256,512,...] [-r reps] [-b cpu,gpu,npu]\n", argv[0]);
			return 2;
		}
	}

	printf("%-4s %6s %10s %10s %9s %10s\n", "", "n", "total ms", "kernel ms", "GFLOP/s", "rel err");

	char sbuf[256], *tok, *save;
	snprintf(sbuf, sizeof(sbuf), "%s", sizes);
	for (tok = strtok_r(sbuf, ",", &save); tok; tok = strtok_r(NULL, ",", &save)) {
		int n = atoi(tok);
		if (n < 32 || n % 32) {
			fprintf(stderr, "n=%d: must be a multiple of 32\n", n);
			continue;
		}
		size_t len = (size_t)n * n;
		float *A = malloc(len * sizeof(float)), *B = malloc(len * sizeof(float));
		float *C = malloc(len * sizeof(float)), *ref = malloc(len * sizeof(float));

		srand(n);
		for (size_t i = 0; i < len; i++) {
			A[i] = 2.0f * rand() / RAND_MAX - 1.0f;
			B[i] = 2.0f * rand() / RAND_MAX - 1.0f;
		}
		/* the reference: the CPU back end's result */
		double dummy;
		backend_cpu.init(n);
		backend_cpu.run(A, B, ref, n, &dummy);
		float refmax = 0;
		for (size_t i = 0; i < len; i++)
			refmax = fmaxf(refmax, fabsf(ref[i]));

		for (size_t b = 0; b < sizeof(backends) / sizeof(backends[0]); b++) {
			const struct backend *be = backends[b];
			double best = 1e30, best_k = 1e30, k;

			if (!wanted(only, be->name))
				continue;
			if (be->init(n)) {
				printf("%-4s %6d  init failed\n", be->name, n);
				be->fini();
				continue;
			}
			memset(C, 0, len * sizeof(float));
			if (be->run(A, B, C, n, &k)) {	/* warm-up */
				printf("%-4s %6d  run failed\n", be->name, n);
				be->fini();
				continue;
			}
			for (int r = 0; r < reps; r++) {
				double t0 = now();
				be->run(A, B, C, n, &k);
				double t = now() - t0;
				if (t < best)
					best = t;
				if (k < best_k)
					best_k = k;
			}
			float err = 0;
			for (size_t i = 0; i < len; i++)
				err = fmaxf(err, fabsf(C[i] - ref[i]));
			printf("%-4s %6d %10.3f %10.3f %9.1f %10.1e\n", be->name, n, best * 1e3, best_k * 1e3,
			       2.0 * n * n * n / best_k / 1e9, err / refmax);
			be->fini();
		}
		free(A); free(B); free(C); free(ref);
	}
	return 0;
}
