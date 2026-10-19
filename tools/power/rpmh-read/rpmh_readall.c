// SPDX-License-Identifier: GPL-2.0-only
/*
 * rpmh_readall: read back RPMh resource settings with rpmh_read() (backported
 * from linux-next, edbafe65eef2) for a list of addresses, through the APSS
 * RSC (Linux's DRV). Resources no Linux driver ever votes keep whatever the
 * bootloader voted; our RPMh traces could never show those.
 *   insmod rpmh_readall.ko addrs=0x30000,0x50000,...
 * Read-only. Stops after 3 consecutive failed reads.
 *
 * DO NOT LOAD on X1E: on 19 Oct 2026 (7.2.7 + edbafe65eef2/e284de4dfc01,
 * EL1) the first read hung the whole machine: the read never completes, the
 * active TCS stays busy and every RPMh client blocks behind it.
 */
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <soc/qcom/rpmh.h>
#include <soc/qcom/tcs.h>

static uint addrs[512];
static int naddrs;
module_param_array(addrs, uint, &naddrs, 0444);

#define CLIENT "/soc@0/rsc@17500000/clock-controller"	/* any child of apps_rsc */

static int __init rpmh_readall_init(void)
{
	struct device_node *np = of_find_node_by_path(CLIENT);
	struct platform_device *pdev;
	int i, ret, fails = 0, ok = 0;

	if (!np)
		return -ENODEV;
	pdev = of_find_device_by_node(np);
	of_node_put(np);
	if (!pdev)
		return -ENODEV;

	for (i = 0; i < naddrs && fails < 3; i++) {
		struct tcs_cmd cmd = { .addr = addrs[i] };

		ret = rpmh_read(&pdev->dev, &cmd);
		if (ret) {
			fails++;
			pr_info("rpmh_readall: 0x%05x error %d\n", addrs[i], ret);
			continue;
		}
		fails = 0;
		ok++;
		pr_info("rpmh_readall: 0x%05x = 0x%08x\n", addrs[i], cmd.data);
	}
	pr_info("rpmh_readall: %d of %d read%s\n", ok, naddrs,
		fails >= 3 ? " (stopped after 3 consecutive errors)" : "");
	put_device(&pdev->dev);
	return 0;
}

static void __exit rpmh_readall_exit(void) { }

module_init(rpmh_readall_init);
module_exit(rpmh_readall_exit);
MODULE_DESCRIPTION("Read back RPMh resource settings (debugging)");
MODULE_LICENSE("GPL");
