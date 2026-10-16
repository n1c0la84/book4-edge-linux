// SPDX-License-Identifier: GPL-2.0-only
/*
 * gdsc_drips: debugging aid for X1E80100 suspend. Linux never switches the
 * USB GDSCs off: they are PWRSTS_RET_ON, so gdsc_disable() leaves them on and
 * relies on hardware retention once CX collapses. Windows' PEP instead
 * switches exactly these footswitches around its low-power state (CSRL
 * "SUPPRESSIBLE_RESOURCES" in qcpep8380's INF). This module collapses them
 * (SW_COLLAPSE, flops retained by RETAIN_FF_ENABLE) at the start of the noirq
 * suspend phase, after every device's normal suspend callback, and restores
 * the ones it collapsed at the end of noirq resume.
 *
 * Only safe with USB wakeup disabled (dwc3 then exits its core and PHYs in
 * suspend and re-initialises them on resume).
 *
 *   insmod gdsc_drips.ko [mask=0x3ff]    bit n = gdscs[n] below
 */
#include <linux/bits.h>
#include <linux/io.h>
#include <linux/iopoll.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/pm.h>

#define GCC_BASE		0x100000
#define GCC_SIZE		0x200000
#define PWR_ON			BIT(31)
#define SW_COLLAPSE		BIT(0)
#define CFG_GDSCR		0x4
#define POWER_UP_COMPLETE	BIT(16)
#define POWER_DOWN_COMPLETE	BIT(15)

static const struct { const char *name; u32 gdscr; } gdscs[] = {
	{ "gcc_usb30_prim_gdsc",	0x39004 },
	{ "gcc_usb30_sec_gdsc",		0xa1004 },
	{ "gcc_usb20_prim_gdsc",	0x29004 },
	{ "gcc_usb_0_phy_gdsc",		0x50024 },
	{ "gcc_usb_1_phy_gdsc",		0x2a024 },
	{ "gcc_usb_2_phy_gdsc",		0xa3024 },
	{ "gcc_usb30_tert_gdsc",	0xa2004 },
	{ "gcc_usb30_mp_gdsc",		0x17004 },
	{ "gcc_usb3_mp_ss0_phy_gdsc",	0x1900c },
	{ "gcc_usb3_mp_ss1_phy_gdsc",	0x5400c },
};

static unsigned int mask = GENMASK(ARRAY_SIZE(gdscs) - 1, 0);
module_param(mask, uint, 0444);
MODULE_PARM_DESC(mask, "bit n collapses gdscs[n] in suspend (default all ten)");

static void __iomem *gcc;
static unsigned long collapsed;
static struct platform_device *pdev;

static int gdsc_drips_suspend_noirq(struct device *dev)
{
	int i, n = 0;
	u32 v;

	collapsed = 0;
	for (i = 0; i < ARRAY_SIZE(gdscs); i++) {
		void __iomem *r = gcc + gdscs[i].gdscr;

		if (!(mask & BIT(i)))
			continue;
		v = readl(r);
		if ((v & SW_COLLAPSE) || !(v & PWR_ON))
			continue;			/* already off */
		writel(v | SW_COLLAPSE, r);
		if (readl_poll_timeout_atomic(r + CFG_GDSCR, v, v & POWER_DOWN_COMPLETE, 1, 2000)) {
			dev_warn(dev, "%s did not power down (gdscr %08x cfg %08x), restoring\n",
				 gdscs[i].name, readl(r), v);
			writel(readl(r) & ~SW_COLLAPSE, r);
			continue;
		}
		__set_bit(i, &collapsed);
		n++;
	}
	dev_info(dev, "collapsed %d USB GDSCs (mask %#lx)\n", n, collapsed);
	return 0;
}

static int gdsc_drips_resume_noirq(struct device *dev)
{
	int i;
	u32 v;

	for_each_set_bit(i, &collapsed, ARRAY_SIZE(gdscs)) {
		void __iomem *r = gcc + gdscs[i].gdscr;

		v = readl(r);
		if (v & SW_COLLAPSE)	/* genpd may already have powered it on */
			writel(v & ~SW_COLLAPSE, r);
		if (readl_poll_timeout_atomic(r + CFG_GDSCR, v, v & POWER_UP_COMPLETE, 1, 2000))
			dev_err(dev, "%s did not power up again (cfg %08x)\n", gdscs[i].name, v);
	}
	dev_info(dev, "restored USB GDSCs %#lx\n", collapsed);
	collapsed = 0;
	return 0;
}

static const struct dev_pm_ops gdsc_drips_pm = {
	NOIRQ_SYSTEM_SLEEP_PM_OPS(gdsc_drips_suspend_noirq, gdsc_drips_resume_noirq)
};

static struct platform_driver gdsc_drips_driver = {
	.driver = { .name = "gdsc_drips", .pm = &gdsc_drips_pm },
};

static int __init gdsc_drips_init(void)
{
	int ret;

	gcc = ioremap(GCC_BASE, GCC_SIZE);
	if (!gcc)
		return -ENOMEM;
	ret = platform_driver_register(&gdsc_drips_driver);
	if (ret)
		goto unmap;
	/*
	 * Registered last, so in the noirq phase this device suspends first and
	 * resumes last; every device's normal suspend callback has run by then.
	 */
	pdev = platform_device_register_simple("gdsc_drips", -1, NULL, 0);
	if (IS_ERR(pdev)) {
		ret = PTR_ERR(pdev);
		goto unreg;
	}
	pr_info("gdsc_drips: will collapse USB GDSCs %#x in suspend\n", mask);
	return 0;
unreg:
	platform_driver_unregister(&gdsc_drips_driver);
unmap:
	iounmap(gcc);
	return ret;
}

static void __exit gdsc_drips_exit(void)
{
	platform_device_unregister(pdev);
	platform_driver_unregister(&gdsc_drips_driver);
	iounmap(gcc);
}

module_init(gdsc_drips_init);
module_exit(gdsc_drips_exit);
MODULE_DESCRIPTION("Collapse X1E80100 USB GDSCs in suspend (debugging)");
MODULE_LICENSE("GPL");
