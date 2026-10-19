// SPDX-License-Identifier: GPL-2.0
/* From github.com/justririll/x1e-sleep (commit 4e84b60), unchanged. EL2 only. */
/*
 * Linux at EL2 (VHE) runs its tick on the EL2 physical timer (CNTHP), but the
 * secure firmware derives the APSS wake deadline for cluster/system power
 * collapse from the EL1 timers (CNTP/CNTV), which Windows and EL1 Linux use.
 *
 * - Before a CPU enters a power-down idle state (CPU_PM_ENTER), copy its CNTHP
 *   deadline into CNTP_*_EL02 with the interrupt masked, so the firmware
 *   programs the wake-up for the real next timer event; on exit park it far
 *   away again.
 * - Disable the EL1 virtual timer left armed (and long expired) by UEFI on the
 *   boot CPU; it made the firmware abort every system-level entry at once.
 *
 * Do not load while KVM guests run (KVM owns the EL1 timers then).
 */
#include <linux/module.h>
#include <linux/smp.h>
#include <linux/cpu.h>
#include <linux/cpu_pm.h>
#include <asm/sysreg.h>
#include <asm/arch_timer.h>

#define FAR_TICKS	(1ULL << 44)	/* ~10 days at 19.2 MHz */
#define CTL_EN		ARCH_TIMER_CTRL_ENABLE
#define CTL_MASK	ARCH_TIMER_CTRL_IT_MASK

static void park(void)
{
	write_sysreg_s(__arch_counter_get_cntpct() + FAR_TICKS, SYS_CNTP_CVAL_EL02);
	write_sysreg_s(CTL_EN | CTL_MASK, SYS_CNTP_CTL_EL02);
	isb();
}

static int el1tmr_cpu_pm(struct notifier_block *nb, unsigned long action, void *v)
{
	u64 ctl;

	switch (action) {
	case CPU_PM_ENTER:
		ctl = read_sysreg(cntp_ctl_el0);	/* CNTHP_CTL_EL2 under VHE */
		if ((ctl & CTL_EN) && !(ctl & CTL_MASK))
			write_sysreg_s(read_sysreg(cntp_cval_el0), SYS_CNTP_CVAL_EL02);
		else
			write_sysreg_s(__arch_counter_get_cntpct() + FAR_TICKS,
				       SYS_CNTP_CVAL_EL02);
		write_sysreg_s(CTL_EN | CTL_MASK, SYS_CNTP_CTL_EL02);
		isb();
		break;
	case CPU_PM_ENTER_FAILED:
	case CPU_PM_EXIT:
		park();
		break;
	}
	return NOTIFY_OK;
}

static struct notifier_block el1tmr_cpu_pm_nb = { .notifier_call = el1tmr_cpu_pm };

static void init_one(void *unused)
{
	park();
	write_sysreg_s(0, SYS_CNTV_CTL_EL02);
	isb();
}

static void exit_one(void *unused)
{
	write_sysreg_s(0, SYS_CNTP_CTL_EL02);
	isb();
}

static int __init el1tmr_init(void)
{
	if (!is_kernel_in_hyp_mode())
		return -ENODEV;
	on_each_cpu(init_one, NULL, 1);
	return cpu_pm_register_notifier(&el1tmr_cpu_pm_nb);
}

static void __exit el1tmr_exit(void)
{
	cpu_pm_unregister_notifier(&el1tmr_cpu_pm_nb);
	on_each_cpu(exit_one, NULL, 1);
}
module_init(el1tmr_init);
module_exit(el1tmr_exit);
MODULE_LICENSE("GPL");
