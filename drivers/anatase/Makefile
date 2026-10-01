# Out-of-tree build of the two Anatase drivers for the Galaxy Book4 Edge.
#   make            build against the running kernel
#   make KDIR=...   build against another kernel's headers
#   sudo make install

obj-m += ene-kb9058-battery.o
obj-m += samsung-emuec.o

KDIR ?= /usr/lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

install: all
	$(MAKE) -C $(KDIR) M=$(PWD) modules_install
	depmod -a
