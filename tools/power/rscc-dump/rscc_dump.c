// SPDX-License-Identifier: GPL-2.0-only
/*
 * rscc_dump: print the non-zero 32-bit words of the display RSC (MDSS RSCC):
 * DRV registers at 0xAF20000 and the wrapper at 0xAF30000 (Qualcomm's layout
 * for this display generation; inside the MDSS ACPI window 0xAE00000+2M).
 * UEFI leaves disp_cc_mdss_rscc_ahb_clk on (enable count 0, hardware Y), so
 * the registers are clocked. Linux never uses this RSC (RPMh DRV 9); any
 * command words in its TCSs were left by firmware.
 *   insmod rscc_dump.ko [len=0x5000] ; dmesg | grep rscc_dump ; rmmod rscc_dump
 * Read-only.
 */
#include <linux/module.h>
#include <linux/io.h>

#define RSCC_DRV	0x0af20000
#define RSCC_WRAPPER	0x0af30000

static uint len = 0x5000;
module_param(len, uint, 0444);

static void dump(const char *name, phys_addr_t pa)
{
	void __iomem *b = ioremap(pa, len);
	unsigned int off, n = 0;

	if (!b) {
		pr_err("rscc_dump: %s: ioremap failed\n", name);
		return;
	}
	for (off = 0; off < len; off += 4) {
		u32 v = readl_relaxed(b + off);

		if (v && n++ < 400)
			pr_info("rscc_dump: %s +0x%04x = 0x%08x\n", name, off, v);
	}
	pr_info("rscc_dump: %s: %u non-zero words in 0x%x bytes\n", name, n, len);
	iounmap(b);
}

static int __init rscc_dump_init(void)
{
	dump("drv", RSCC_DRV);
	dump("wrapper", RSCC_WRAPPER);
	return 0;
}

static void __exit rscc_dump_exit(void) { }

module_init(rscc_dump_init);
module_exit(rscc_dump_exit);
MODULE_DESCRIPTION("Dump the display RSC registers (debugging)");
MODULE_LICENSE("GPL");
