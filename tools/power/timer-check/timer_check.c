// SPDX-License-Identifier: GPL-2.0-only
/*
 * timer_check: at EL2 (VHE), print on every CPU the control registers of
 * the EL1 timers (CNTV/CNTP via the _EL02 aliases) and of the EL2 timers
 * (CNTHV/CNTHP). An enabled, expired timer (ENABLE=1, IMASK=0, ISTATUS=1)
 * keeps its PPI pending, which can make firmware abort a power collapse.
 *   insmod timer_check.ko [disable=1]   disable=1 clears ENABLE on CNTV/CNTP_EL02
 * Refuses to load unless the kernel runs at EL2.
 */
#include <linux/module.h>
#include <linux/smp.h>
#include <asm/sysreg.h>
#include <asm/virt.h>

static bool disable;
module_param(disable, bool, 0444);

#define R_CNTV_CTL_EL02  sys_reg(3, 5, 14, 3, 1)
#define R_CNTP_CTL_EL02  sys_reg(3, 5, 14, 2, 1)
#define R_CNTHV_CTL_EL2  sys_reg(3, 4, 14, 3, 1)
#define R_CNTHP_CTL_EL2  sys_reg(3, 4, 14, 2, 1)

static void dump(void *unused)
{
	u64 v = read_sysreg_s(R_CNTV_CTL_EL02), p = read_sysreg_s(R_CNTP_CTL_EL02);
	u64 hv = read_sysreg_s(R_CNTHV_CTL_EL2), hp = read_sysreg_s(R_CNTHP_CTL_EL2);

	pr_info("timer_check: cpu%d CNTV_EL02=%llx CNTP_EL02=%llx CNTHV_EL2=%llx CNTHP_EL2=%llx (bit0 ENABLE, bit1 IMASK, bit2 ISTATUS)\n",
		smp_processor_id(), v, p, hv, hp);
	if (disable) {
		write_sysreg_s(v & ~1ULL, R_CNTV_CTL_EL02);
		write_sysreg_s(p & ~1ULL, R_CNTP_CTL_EL02);
		isb();
	}
}

static int __init timer_check_init(void)
{
	if (!is_kernel_in_hyp_mode()) {
		pr_err("timer_check: not at EL2, refusing\n");
		return -ENODEV;
	}
	on_each_cpu(dump, NULL, 1);
	if (disable)
		pr_info("timer_check: EL1 virtual/physical timers disabled on all CPUs\n");
	return 0;
}

static void __exit timer_check_exit(void) { }

module_init(timer_check_init);
module_exit(timer_check_exit);
MODULE_DESCRIPTION("Show (and optionally disable) leftover EL1 timers at EL2");
MODULE_LICENSE("GPL");
