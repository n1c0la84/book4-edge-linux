// SPDX-License-Identifier: GPL-2.0-only
/*
 * cntv_arm: give the firmware a wake deadline in s2idle, for Linux at EL1.
 *
 * The secure firmware derives the APSS wake-up deadline for cluster/system
 * power collapse from the EL1 timers. Linux at EL1 ticks on the EL1 virtual
 * timer (CNTV). In s2idle, tick_freeze() stops the clockevent, which clears
 * CNTV_CTL.ENABLE, and the firmware then holds the system-level request
 * without collapsing APSS (reported on an XPS 13 9345 by Michael Burch,
 * linux-arm-msm, 8 Oct 2026; the EL2 counterpart is el1tmr in
 * github.com/justririll/x1e-sleep).
 *
 * At every CPU_PM_ENTER where CNTV is disabled, arm it with a deadline far in
 * the future; at CPU_PM_EXIT or CPU_PM_ENTER_FAILED put it back to disabled.
 * While the tick runs CNTV is enabled and nothing is touched.
 *
 * The interrupt is left unmasked (since 13 November 2026). Gunyah only counts
 * a vCPU timer that is enabled AND unmasked (arm_vm_timer_is_irq_enabled() in
 * the public source: ENABLE && !IMASK); a masked one is dequeued at vCPU
 * suspend, so to the hypervisor the CPU has no wake deadline at all. The
 * first version armed it masked, and at EL1 qcom_stats apss never counted.
 * The deadline is days away, and if it ever came the arch timer handler
 * would mask it and return.
 *   masked=1     the old behaviour, for comparison
 *   far_secs=N   deadline N seconds ahead (default: 2^44 ticks, ~10 days)
 *   insmod cntv_arm.ko ; ... ; rmmod cntv_arm   (prints how often it armed)
 * Refuses to load at EL2 (use el1tmr there).
 */
#include <linux/module.h>
#include <linux/cpu_pm.h>
#include <linux/percpu.h>
#include <asm/arch_timer.h>
#include <asm/sysreg.h>
#include <asm/virt.h>

#define FAR_TICKS	(1ULL << 44)	/* ~10 days at 19.2 MHz */

static bool masked;
module_param(masked, bool, 0444);
MODULE_PARM_DESC(masked, "arm CNTV with its interrupt masked (invisible to Gunyah)");
static unsigned int far_secs;
module_param(far_secs, uint, 0444);
MODULE_PARM_DESC(far_secs, "deadline in seconds (0: 2^44 ticks, about 10 days)");

static DEFINE_PER_CPU(bool, armed);
static atomic_t n_armed;

static int cntv_arm_cpu_pm(struct notifier_block *nb, unsigned long action, void *v)
{
	u64 ctl;

	switch (action) {
	case CPU_PM_ENTER:
		ctl = read_sysreg(cntv_ctl_el0);
		if (ctl & ARCH_TIMER_CTRL_ENABLE)
			break;			/* the tick owns it */
		write_sysreg(read_sysreg(cntvct_el0) +
			     (far_secs ? (u64)far_secs * arch_timer_get_cntfrq() : FAR_TICKS),
			     cntv_cval_el0);
		write_sysreg(ARCH_TIMER_CTRL_ENABLE | (masked ? ARCH_TIMER_CTRL_IT_MASK : 0),
			     cntv_ctl_el0);
		isb();
		this_cpu_write(armed, true);
		atomic_inc(&n_armed);
		break;
	case CPU_PM_ENTER_FAILED:
	case CPU_PM_EXIT:
		if (this_cpu_read(armed)) {
			write_sysreg(0, cntv_ctl_el0);
			isb();
			this_cpu_write(armed, false);
		}
		break;
	}
	return NOTIFY_OK;
}

static struct notifier_block cntv_arm_nb = { .notifier_call = cntv_arm_cpu_pm };

static int __init cntv_arm_init(void)
{
	if (is_kernel_in_hyp_mode()) {
		pr_err("cntv_arm: kernel at EL2, refusing (use el1tmr)\n");
		return -ENODEV;
	}
	return cpu_pm_register_notifier(&cntv_arm_nb);
}

static void __exit cntv_arm_exit(void)
{
	cpu_pm_unregister_notifier(&cntv_arm_nb);
	pr_info("cntv_arm: armed CNTV at %d CPU_PM entries (%s, %u s)\n",
		atomic_read(&n_armed), masked ? "masked" : "unmasked", far_secs);
}

module_init(cntv_arm_init);
module_exit(cntv_arm_exit);
MODULE_DESCRIPTION("Arm the EL1 virtual timer across s2idle power-down (X1E, EL1)");
MODULE_LICENSE("GPL");
