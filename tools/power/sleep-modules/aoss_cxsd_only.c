// SPDX-License-Identifier: GPL-2.0-only
/* From github.com/justririll/x1e-sleep (commit 4e84b60), unchanged. */
/*
 * Workaround: keep the SoC out of AOSD (XO shutdown) and allow only CX
 * collapse. On the Vivobook S15 (EL2, no Gunyah) the SoC resets about once
 * an hour while in AOSD; with AOSD disabled it sleeps through at ~0.17 W.
 *
 * Sends "{class: aoss_slp, res: sleep, val: disable}" to the AOSS over the
 * existing QMP transport at load and re-enables AOSD on unload.
 */
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>

struct qmp;
int qmp_send(struct qmp *qmp, const char *fmt, ...);

static struct platform_device *aoss_pdev;

static struct qmp *aoss_qmp(void)
{
	return aoss_pdev ? platform_get_drvdata(aoss_pdev) : NULL;
}

static int __init aoss_cxsd_only_init(void)
{
	struct device_node *np;
	struct qmp *qmp;
	int ret;

	np = of_find_compatible_node(NULL, NULL, "qcom,aoss-qmp");
	if (!np)
		return -ENODEV;
	aoss_pdev = of_find_device_by_node(np);
	of_node_put(np);
	if (!aoss_pdev)
		return -ENODEV;

	qmp = aoss_qmp();
	if (!qmp) {
		put_device(&aoss_pdev->dev);
		return -EPROBE_DEFER;
	}

	ret = qmp_send(qmp, "{class: aoss_slp, res: sleep, val: disable}");
	if (ret) {
		put_device(&aoss_pdev->dev);
		return ret;
	}
	pr_info("aoss_cxsd_only: AOSD disabled, system sleep stops at CXSD\n");
	return 0;
}

static void __exit aoss_cxsd_only_exit(void)
{
	qmp_send(aoss_qmp(), "{class: aoss_slp, res: sleep, val: enable}");
	pr_info("aoss_cxsd_only: AOSD enabled again\n");
	put_device(&aoss_pdev->dev);
}

module_init(aoss_cxsd_only_init);
module_exit(aoss_cxsd_only_exit);
MODULE_SOFTDEP("pre: qcom_aoss");
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Disable AOSD (XO shutdown) via AOSS QMP; CX collapse only");
