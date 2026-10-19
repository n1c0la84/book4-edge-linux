// SPDX-License-Identifier: GPL-2.0-only
/*
 * rscc_dump: print the non-zero 32-bit words of the display RSC (MDSS RSCC):
 * DRV registers at 0xAF20000 and the wrapper at 0xAF30000 (Qualcomm's layout
 * for this display generation; inside the MDSS ACPI window 0xAE00000+2M).
 * UEFI leaves disp_cc_mdss_rscc_ahb_clk on (enable count 0, hardware Y), so
 * the registers are clocked. Linux never uses this RSC (RPMh DRV 9); any
 * command words in its TCSs were left by firmware.
 *   insmod rscc_dump.ko stage=N ; dmesg | grep rscc_dump ; rmmod rscc_dump
 * stage 0: only the ID word (+0x0) of each region; a sane RSC ID has the
 *          version in bits 23:16 / 15:8 (rpmh-rsc's RSC_DRV_ID)
 * stage 1: first 0x100 bytes (ID, solver and TCS configuration)
 * stage 2: non-zero words of the first 0x5000 bytes. RESET the machine at
 *          EL2 on 19 Oct (holes or protected sub-blocks); do not use.
 * stage 3: only the two TCSs (sleep, wake) at tcs-offset 0x1c00, stride 672,
 *          16 commands of 24 bytes (RSC v3.0 layout, as rpmh-rsc reads the
 *          apps RSC): enable mask, then address/data of each command.
 * Stage 1 matched Qualcomm's downstream display-RSC map (+0x20..+0x2c PDC
 * sequencer/match/slave ID; 2 TCSs, 16 commands each, HW solver).
 * Read-only, but at EL1 under Gunyah the first read reset the machine
 * (19 Oct): the region is not mapped for the Linux VM. EL2 only.
 */
#include <linux/module.h>
#include <linux/io.h>
#include <asm/virt.h>

#define RSCC_DRV	0x0af20000
#define RSCC_WRAPPER	0x0af30000

static uint stage;
module_param(stage, uint, 0444);
static uint len;

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

		if ((v || stage == 0) && n++ < 400)
			pr_info("rscc_dump: %s +0x%04x = 0x%08x\n", name, off, v);
	}
	pr_info("rscc_dump: %s: %u non-zero words in 0x%x bytes\n", name, n, len);
	iounmap(b);
}

#define TCS_OFFSET	0x1c00
#define TCS_STRIDE	672
#define CMD_STRIDE	24

static void dump_tcs(void)
{
	void __iomem *b = ioremap(RSCC_DRV + TCS_OFFSET, 2 * TCS_STRIDE);
	int t, c;

	if (!b) {
		pr_err("rscc_dump: tcs: ioremap failed\n");
		return;
	}
	for (t = 0; t < 2; t++) {
		void __iomem *tb = b + t * TCS_STRIDE;
		u32 en = readl_relaxed(tb + 0x2c);	/* RSC_DRV_CMD_ENABLE */

		pr_info("rscc_dump: tcs%d control 0x%08x status 0x%08x wait 0x%08x enable 0x%04x\n",
			t, readl_relaxed(tb + 0x24), readl_relaxed(tb + 0x28),
			readl_relaxed(tb + 0x20), en);
		for (c = 0; c < 16; c++) {
			void __iomem *cb = tb + c * CMD_STRIDE;
			u32 msgid = readl_relaxed(cb + 0x34), addr = readl_relaxed(cb + 0x38);
			u32 data = readl_relaxed(cb + 0x3c), st = readl_relaxed(cb + 0x40);

			if (msgid || addr || data)
				pr_info("rscc_dump: tcs%d cmd%-2d %s msgid 0x%08x addr 0x%05x data 0x%08x status 0x%08x\n",
					t, c, en & BIT(c) ? "EN " : "off", msgid, addr, data, st);
		}
	}
	iounmap(b);
}

static int __init rscc_dump_init(void)
{
	if (!is_kernel_in_hyp_mode()) {
		pr_err("rscc_dump: not at EL2, refusing (it reset the machine at EL1)\n");
		return -EPERM;
	}
	if (stage == 3) {
		dump_tcs();
		return 0;
	}
	if (stage == 2) {
		pr_err("rscc_dump: stage 2 reset the machine; use stage 3\n");
		return -EINVAL;
	}
	len = stage == 0 ? 4 : 0x100;
	pr_info("rscc_dump: stage %u, 0x%x bytes per region\n", stage, len);
	dump("drv", RSCC_DRV);
	dump("wrapper", RSCC_WRAPPER);
	return 0;
}

static void __exit rscc_dump_exit(void) { }

module_init(rscc_dump_init);
module_exit(rscc_dump_exit);
MODULE_DESCRIPTION("Dump the display RSC registers (debugging)");
MODULE_LICENSE("GPL");
