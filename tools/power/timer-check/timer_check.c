// SPDX-License-Identifier: GPL-2.0-only
/*
 * timer_check: at EL2 (VHE), print on every CPU the control registers of
 * the EL1 timers (CNTV/CNTP via the _EL02 aliases) and of the EL2 timers
 * (CNTHV/CNTHP). An enabled, expired timer (ENABLE=1, IMASK=0, ISTATUS=1)
 * keeps its PPI pending, which can make firmware abort a power collapse.
 *   insmod timer_check.ko [disable=1]   disable=1 clears ENABLE on CNTV/CNTP_EL02,
 *   also at every CPU_PM_ENTER/EXIT (a core power collapse may leave them armed);
 *   on unload, prints how often they were found enabled at CPU_PM_EXIT
 * Refuses to load unless the kernel runs at EL2.
 */
#include <linux/module.h>
#include <linux/cpu_pm.h>
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

static atomic_t exits, armed_v, armed_p;

static int pm_notify(struct notifier_block *nb, unsigned long action, void *v)
{
	u64 cv, cp;

	if (action != CPU_PM_ENTER && action != CPU_PM_EXIT)
		return NOTIFY_OK;
	cv = read_sysreg_s(R_CNTV_CTL_EL02);
	cp = read_sysreg_s(R_CNTP_CTL_EL02);
	if (action == CPU_PM_EXIT) {
		atomic_inc(&exits);
		if (cv & 1) atomic_inc(&armed_v);
		if (cp & 1) atomic_inc(&armed_p);
	}
	if ((cv | cp) & 1) {
		write_sysreg_s(cv & ~1ULL, R_CNTV_CTL_EL02);
		write_sysreg_s(cp & ~1ULL, R_CNTP_CTL_EL02);
		isb();
	}
	return NOTIFY_OK;
}

static struct notifier_block pm_nb = { .notifier_call = pm_notify };

static int __init timer_check_init(void)
{
	if (!is_kernel_in_hyp_mode()) {
		pr_err("timer_check: not at EL2, refusing\n");
		return -ENODEV;
	}
	on_each_cpu(dump, NULL, 1);
	if (disable) {
		cpu_pm_register_notifier(&pm_nb);
		pr_info("timer_check: EL1 virtual/physical timers disabled on all CPUs and at every CPU_PM entry/exit\n");
	}
	return 0;
}

static void __exit timer_check_exit(void)
{
	if (!disable)
		return;
	cpu_pm_unregister_notifier(&pm_nb);
	pr_info("timer_check: %d CPU_PM exits, CNTV_EL02 enabled at %d, CNTP_EL02 enabled at %d\n",
		atomic_read(&exits), atomic_read(&armed_v), atomic_read(&armed_p));
}

module_init(timer_check_init);
module_exit(timer_check_exit);
MODULE_DESCRIPTION("Show (and optionally disable) leftover EL1 timers at EL2");
MODULE_LICENSE("GPL");
