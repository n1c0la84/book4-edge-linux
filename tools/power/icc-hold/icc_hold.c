// SPDX-License-Identifier: GPL-2.0-only
/*
 * icc_hold: debugging aid. Holds a maximum interconnect vote on every path
 * declared ("interconnects" property) by the given devicetree nodes, until
 * the module is unloaded. Used to find which path a device needs across
 * suspend/resume once the boot-time bandwidth floors are gone.
 *
 *   insmod icc_hold.ko all=1                      every node with interconnects
 *   insmod icc_hold.ko nodes=/soc@0/ufshc@1d84000,/soc@0/pci@1c08000
 *   insmod icc_hold.ko all=1 skip=/cpus/cpu@0     everything but some nodes
 *   insmod icc_hold.ko nodes=/soc@0/ufshc@1d84000 index=1   only path 1
 *   optional: tag=7 (QCOM_ICC_TAG_ALWAYS, default) or tag=3 (ACTIVE_ONLY)
 */
#include <linux/err.h>
#include <linux/interconnect.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/slab.h>
#include <linux/string.h>

#define MAX_PATHS 256
#define MAX_ARGS 64

static bool all;
module_param(all, bool, 0444);
MODULE_PARM_DESC(all, "hold the paths of every DT node with an interconnects property");

static char *nodes[MAX_ARGS];
static int nodes_n;
module_param_array(nodes, charp, &nodes_n, 0444);
MODULE_PARM_DESC(nodes, "comma-separated DT node paths whose interconnect paths to hold");

static char *skip[MAX_ARGS];
static int skip_n;
module_param_array(skip, charp, &skip_n, 0444);
MODULE_PARM_DESC(skip, "with all=1: DT node paths (or prefixes) to leave alone");

static int path_index = -1;
module_param_named(index, path_index, int, 0444);
MODULE_PARM_DESC(index, "with nodes=: hold only this path index of each node (-1 = all)");

static unsigned int tag = 7;
module_param(tag, uint, 0444);
MODULE_PARM_DESC(tag, "interconnect tag (7 = always, 3 = active only)");

static struct platform_device *pdev;
static struct icc_path *paths[MAX_PATHS];
static int npaths;

static bool skipped(const char *full)
{
	int i;

	for (i = 0; i < skip_n; i++)
		if (!strncmp(full, skip[i], strlen(skip[i])))
			return true;
	return false;
}

static void hold_node(struct device_node *np, int only)
{
	char *full;
	int idx;

	full = kasprintf(GFP_KERNEL, "%pOF", np);
	if (!full)
		return;
	if (skipped(full))
		goto out;

	pdev->dev.of_node = np;
	for (idx = 0; idx < 16 && npaths < MAX_PATHS; idx++) {
		struct icc_path *p = of_icc_get_by_index(&pdev->dev, idx);

		if (IS_ERR_OR_NULL(p))
			break;
		if (only >= 0 && idx != only) {
			icc_put(p);
			continue;
		}
		icc_set_tag(p, tag);
		/*
		 * Peak is aggregated as a maximum, average as a sum: a maximum
		 * peak pins the path, while a maximum average on many paths
		 * would overflow the u32 sum and wrap to a small value.
		 */
		if (icc_set_bw(p, 1, INT_MAX)) {
			pr_warn("icc_hold: %s path %d: set_bw failed\n", full, idx);
			icc_put(p);
			continue;
		}
		paths[npaths++] = p;
		pr_info("icc_hold: holding %s path %d\n", full, idx);
	}
	pdev->dev.of_node = NULL;
out:
	kfree(full);
}

static int __init icc_hold_init(void)
{
	struct device_node *np;
	int i;

	pdev = platform_device_register_simple("icc-hold", PLATFORM_DEVID_NONE, NULL, 0);
	if (IS_ERR(pdev))
		return PTR_ERR(pdev);

	if (all) {
		for_each_node_with_property(np, "interconnects")
			hold_node(np, -1);
	}
	for (i = 0; i < nodes_n; i++) {
		np = of_find_node_by_path(nodes[i]);
		if (!np) {
			pr_warn("icc_hold: no node %s\n", nodes[i]);
			continue;
		}
		hold_node(np, path_index);
		of_node_put(np);
	}
	pr_info("icc_hold: holding %d paths (tag %u)\n", npaths, tag);
	return 0;
}

static void __exit icc_hold_exit(void)
{
	while (npaths)
		icc_put(paths[--npaths]);
	platform_device_unregister(pdev);
	pr_info("icc_hold: released\n");
}

module_init(icc_hold_init);
module_exit(icc_hold_exit);
MODULE_DESCRIPTION("Hold maximum interconnect votes on DT-declared paths (debugging)");
MODULE_LICENSE("GPL");
