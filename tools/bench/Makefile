# SPDX-License-Identifier: GPL-2.0-only
# make            CPU + GPU
# make NPU=1      + NPU (needs npu/out/ from npu/build-dsp.sh and ~/npu/rt)
CC      ?= gcc
CFLAGS  ?= -O3 -mcpu=native
CFLAGS  += -std=gnu11 -Wall -Wextra -fopenmp
LDLIBS  += -lvulkan -lm
NPU_RT  ?= $(HOME)/npu/rt

SRCS = main.c cpu.c gpu.c
ifeq ($(NPU),1)
SRCS    += npu/host.c npu/out/mm_stub.c
CFLAGS  += -DBENCH_NPU -Inpu/out -I$(NPU_RT)/include/fastrpc
LDFLAGS += -L$(NPU_RT)/lib -Wl,-rpath,$(NPU_RT)/lib
LDLIBS  += -lcdsprpc
endif

bench: $(SRCS) backend.h mm.spv.inc
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SRCS) $(LDLIBS)

mm.spv.inc: mm.comp
	glslc -O -mfmt=c -o $@ $<

clean:
	rm -f bench mm.spv.inc

.PHONY: clean
