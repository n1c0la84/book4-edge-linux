// SPDX-License-Identifier: GPL-2.0-only
/*
 * vreg_off: send an explicit "off" vote for RPMh regulators that no Linux
 * driver uses. rpmh-regulator can't read a regulator's state back, so
 * regulators without consumers stay "unknown", regulator_late_cleanup()
 * skips them, and they keep whatever vote UEFI last made on the HLOS DRV.
 * Windows' PEP votes several of them off whenever their device sleeps.
 *   insmod vreg_off.ko names=vreg_l3c_0p8,vreg_l8b_3p0,...
 * Refuses regulators that have users. Reboot to restore UEFI's votes.
 */
#include <linux/module.h>
#include <linux/err.h>
#include <linux/regulator/consumer.h>

static char *names[32];
static int nnames;
module_param_array(names, charp, &nnames, 0444);

static int __init vreg_off_init(void)
{
	int i, ret;

	for (i = 0; i < nnames; i++) {
		struct regulator *reg = regulator_get_optional(NULL, names[i]);

		if (IS_ERR(reg)) {
			pr_warn("vreg_off: %s: not found (%ld)\n", names[i], PTR_ERR(reg));
			continue;
		}
		if (regulator_is_enabled(reg) > 0) {
			pr_warn("vreg_off: %s: enabled by a Linux user, skipped\n", names[i]);
			regulator_put(reg);
			continue;
		}
		ret = regulator_force_disable(reg);
		pr_info("vreg_off: %s: off vote sent (%d)\n", names[i], ret);
		regulator_put(reg);
	}
	return 0;
}

static void __exit vreg_off_exit(void) { }

module_init(vreg_off_init);
module_exit(vreg_off_exit);
MODULE_DESCRIPTION("Vote unused RPMh regulators off (debugging)");
MODULE_LICENSE("GPL");
