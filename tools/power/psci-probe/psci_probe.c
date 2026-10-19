// SPDX-License-Identifier: GPL-2.0-only
/*
 * Book4 EL2/VHE diagnostic, one load per experiment. Observe the SMC wrapper
 * after cpuidle's domain/IRQ preparation, only inside s2idle_loop(), and only
 * CPU_SUSPEND(0x0200c354). Never writes GIC/timer registers or issues SMCs.
 * Both probe traps add latency; this is wrapper latency, not pure EL3 time.
 */
#include <linux/bitops.h>
#include <linux/clocksource.h>
#include <linux/cpu.h>
#include <linux/debugfs.h>
#include <linux/err.h>
#include <linux/io.h>
#include <linux/kprobes.h>
#include <linux/log2.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/percpu.h>
#include <linux/seq_file.h>
#include <linux/slab.h>
#include <linux/smp.h>
#include <linux/uaccess.h>
#include <clocksource/arm_arch_timer.h>
#include <asm/cputype.h>
#include <asm/ptrace.h>
#include <asm/sysreg.h>
#include <asm/virt.h>

#define TARGET_STATE	0x0200c354
#define CPU_SUSPEND64	0xc4000001
#define GICD_BASE	0x17000000
#define GICR_BASE	0x17080000
#define GICR_STRIDE	0x40000
#define NFRAMES		12
#define WORDS		32
#define INTIDS		(WORDS * 32)
#define SAVED		8
#define R_CNTV_EL02	sys_reg(3, 5, 14, 3, 1)
#define R_CNTP_EL02	sys_reg(3, 5, 14, 2, 1)
#define R_CNTHV_EL2	sys_reg(3, 4, 14, 3, 1)
#define R_CNTHP_EL2	sys_reg(3, 4, 14, 2, 1)

/* 0: timing only. Otherwise sample one in N target calls on each CPU. */
static unsigned int sample_every = 256;
module_param(sample_every, uint, 0444);
MODULE_PARM_DESC(sample_every, "0 for timing only, or power of two >= 1");

struct snapshot {
	u32 pending[WORDS], enabled[WORDS];
	u64 isr, hppir1, cntv, cntp, cnthv, cnthp;
};

struct saved_call {
	u64 number, ticks, pstate;
	s32 ret;
	struct snapshot before, after;
};

struct cpu_stats {
	u64 entered, returned, sampled, zero_ticks, backwards, migrated;
	u64 first_tick, last_tick, total_ticks, min_ticks, max_ticks;
	u64 returns[11]; /* 0..-9; index 10 = other */
	u64 hist[2][65]; /* unsampled / sampled; fls64(ticks), 0 means zero */
	u64 none_enabled[2];
	u32 pending[2][INTIDS], enabled[2][INTIDS];
	struct saved_call saved[SAVED]; /* last eight sampled calls */
};

struct call_data {
	u64 start, number, pstate;
	unsigned int cpu;
	bool sample;
	struct snapshot before;
};

static struct cpu_stats __percpu *stats;
static DEFINE_PER_CPU(void __iomem *, sgi_base);
static void __iomem *gicd, *gicr;
static unsigned int nwords;
static struct dentry *debug_dir;
static DEFINE_MUTEX(control_lock);
static bool collecting, running;
static u64 loops, loop_ticks, loop_start, frequency;
static struct kretprobe smc_probe, loop_probe;

static void take_snapshot(struct snapshot *s)
{
	void __iomem *sgi = this_cpu_read(sgi_base);
	unsigned int i;

	/* All reads are non-acknowledging. HPPIR1 sees Group 1, not secure IRQs. */
	s->isr = read_sysreg(isr_el1);
	s->hppir1 = read_sysreg_s(SYS_ICC_HPPIR1_EL1);
	s->cntv = read_sysreg_s(R_CNTV_EL02);
	s->cntp = read_sysreg_s(R_CNTP_EL02);
	s->cnthv = read_sysreg_s(R_CNTHV_EL2);
	s->cnthp = read_sysreg_s(R_CNTHP_EL2);
	s->pending[0] = readl_relaxed(sgi + 0x200);
	s->enabled[0] = readl_relaxed(sgi + 0x100);
	for (i = 1; i < nwords; i++) {
		s->pending[i] = readl_relaxed(gicd + 0x200 + 4 * i);
		s->enabled[i] = readl_relaxed(gicd + 0x100 + 4 * i);
	}
}
NOKPROBE_SYMBOL(take_snapshot);

static void count_snapshot(struct cpu_stats *s, const struct snapshot *v, int side)
{
	unsigned int i, bit;
	bool any = false;

	for (i = 0; i < nwords; i++) {
		u32 w = v->pending[i];

		while (w) {
			bit = __ffs(w);
			s->pending[side][32 * i + bit]++;
			if (v->enabled[i] & BIT(bit)) {
				s->enabled[side][32 * i + bit]++;
				any = true;
			}
			w &= w - 1;
		}
	}
	if (!any)
		s->none_enabled[side]++;
}
NOKPROBE_SYMBOL(count_snapshot);

static int smc_enter(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	struct call_data *d = (void *)ri->data;
	struct cpu_stats *s;

	if (!READ_ONCE(collecting) || regs->regs[0] != CPU_SUSPEND64 ||
	    regs->regs[1] != TARGET_STATE)
		return 1; /* Do not install a return handler for other SMCs. */
	d->cpu = smp_processor_id();
	s = this_cpu_ptr(stats);
	d->number = ++s->entered;
	d->sample = sample_every && !(d->number & (sample_every - 1)) &&
		    this_cpu_read(sgi_base);
	d->pstate = regs->pstate; /* interrupted context, not probe-handler DAIF */
	if (d->sample)
		take_snapshot(&d->before);
	d->start = arch_timer_read_counter(); /* exclude pre-snapshot MMIO cost */
	return 0;
}
NOKPROBE_SYMBOL(smc_enter);

static int smc_return(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	u64 end = arch_timer_read_counter(); /* before post-snapshot work */
	struct call_data *d = (void *)ri->data;
	struct cpu_stats *s = per_cpu_ptr(stats, d->cpu);
	struct snapshot after;
	s32 ret = (s32)regs_return_value(regs); /* raw PSCI, not Linux errno */
	u64 ticks = end - d->start;

	if (smp_processor_id() != d->cpu) {
		/* Retention should resume on the same CPU; invalidate the run. */
		s->migrated++;
		return 0;
	}
	if (d->sample)
		take_snapshot(&after);
	if (!s->returned)
		s->first_tick = d->start;
	s->last_tick = end;
	s->returned++;
	s->returns[ret <= 0 && ret >= -9 ? -ret : 10]++;
	if (end < d->start) {
		s->backwards++;
		return 0;
	}
	s->zero_ticks += !ticks;
	s->total_ticks += ticks;
	s->min_ticks = min(s->min_ticks, ticks);
	s->max_ticks = max(s->max_ticks, ticks);
	s->hist[d->sample][fls64(ticks)]++;
	if (d->sample) {
		struct saved_call *v = &s->saved[s->sampled % SAVED];

		count_snapshot(s, &d->before, 0);
		count_snapshot(s, &after, 1);
		v->number = d->number;
		v->ticks = ticks;
		v->ret = ret;
		v->pstate = d->pstate;
		v->before = d->before;
		v->after = after;
		s->sampled++;
	}
	return 0;
}
NOKPROBE_SYMBOL(smc_return);

static int loop_enter(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	loop_start = arch_timer_read_counter();
	WRITE_ONCE(collecting, true);
	return 0;
}
NOKPROBE_SYMBOL(loop_enter);

static int loop_return(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	WRITE_ONCE(collecting, false);
	loop_ticks += arch_timer_read_counter() - loop_start;
	loops++;
	return 0;
}
NOKPROBE_SYMBOL(loop_return);

static void find_frame(void *unused)
{
	u64 mpidr = read_cpuid_mpidr();
	u32 aff = (MPIDR_AFFINITY_LEVEL(mpidr, 3) << 24) |
		  (MPIDR_AFFINITY_LEVEL(mpidr, 2) << 16) |
		  (MPIDR_AFFINITY_LEVEL(mpidr, 1) << 8) |
		  MPIDR_AFFINITY_LEVEL(mpidr, 0);
	unsigned int i;

	for (i = 0; i < NFRAMES; i++) {
		void __iomem *frame = gicr + i * GICR_STRIDE;

		if ((readq_relaxed(frame + 8) >> 32) == aff) {
			this_cpu_write(sgi_base, frame + 0x10000);
			return;
		}
	}
}

/* Called with control_lock held. unregister drains in-flight handlers. */
static void stop_probe(void)
{
	if (!running)
		return;
	WRITE_ONCE(collecting, false);
	unregister_kretprobe(&loop_probe);
	unregister_kretprobe(&smc_probe);
	running = false;
}

static ssize_t stop_write(struct file *f, const char __user *buf,
			  size_t len, loff_t *pos)
{
	char c;

	if (!len || get_user(c, buf))
		return -EFAULT;
	if (c != '1')
		return -EINVAL;
	mutex_lock(&control_lock);
	stop_probe();
	mutex_unlock(&control_lock);
	return len;
}

static const struct file_operations stop_fops = {
	.owner = THIS_MODULE,
	.write = stop_write,
	.llseek = no_llseek,
};

static void print_snapshot(struct seq_file *m, const char *side,
			   const struct snapshot *s)
{
	unsigned int i;

	seq_printf(m, "  %s isr=%#llx hppir1=%llu cntv=%#llx cntp=%#llx cnthv=%#llx cnthp=%#llx\n",
		   side, s->isr, s->hppir1, s->cntv, s->cntp, s->cnthv, s->cnthp);
	for (i = 0; i < nwords; i++)
		if (s->pending[i])
			seq_printf(m, "  %s word=%u pending=%08x enabled=%08x\n",
				   side, i, s->pending[i], s->enabled[i]);
}

static int report_show(struct seq_file *m, void *unused)
{
	unsigned int cpu, i, j;
	int ret = 0;

	mutex_lock(&control_lock);
	if (running) {
		ret = -EBUSY;
		goto out;
	}
	seq_printf(m, "format=1 state=%#x counter_hz=%llu sample_every=%u loops=%llu loop_ticks=%llu smc_nmissed=%d smc_kp_nmissed=%lu loop_nmissed=%d loop_kp_nmissed=%lu\n",
		   TARGET_STATE, frequency, sample_every, loops, loop_ticks,
		   smc_probe.nmissed, smc_probe.kp.nmissed,
		   loop_probe.nmissed, loop_probe.kp.nmissed);
	for_each_possible_cpu(cpu) {
		struct cpu_stats *s = per_cpu_ptr(stats, cpu);

		if (!s->entered)
			continue;
		seq_printf(m, "cpu=%u entered=%llu returned=%llu sampled=%llu zero_ticks=%llu backwards=%llu migrated=%llu first_tick=%llu last_tick=%llu total_ticks=%llu min_ticks=%llu max_ticks=%llu pre_none_enabled=%llu post_none_enabled=%llu\n",
			   cpu, s->entered, s->returned, s->sampled,
			   s->zero_ticks, s->backwards, s->migrated,
			   s->first_tick, s->last_tick, s->total_ticks,
			   s->returned ? s->min_ticks : 0, s->max_ticks,
			   s->none_enabled[0], s->none_enabled[1]);
		for (i = 0; i < ARRAY_SIZE(s->returns); i++)
			if (s->returns[i])
				seq_printf(m, "return cpu=%u code=%d count=%llu\n",
					   cpu, i == 10 ? 999 : -(int)i,
					   s->returns[i]);
		for (i = 0; i < 2; i++)
			for (j = 0; j < 65; j++)
				if (s->hist[i][j])
					seq_printf(m, "hist cpu=%u sampled=%u fls_ticks=%u count=%llu\n",
						   cpu, i, j, s->hist[i][j]);
		for (i = 0; i < INTIDS; i++)
			if (s->pending[0][i] || s->pending[1][i])
				seq_printf(m, "irq cpu=%u intid=%u pre_pending=%u pre_enabled=%u post_pending=%u post_enabled=%u\n",
					   cpu, i, s->pending[0][i], s->enabled[0][i],
					   s->pending[1][i], s->enabled[1][i]);
		for (i = 0; i < min_t(u64, s->sampled, SAVED); i++) {
			struct saved_call *v = &s->saved[i];

			seq_printf(m, "sample cpu=%u number=%llu ticks=%llu ret=%d pstate=%#llx\n",
				   cpu, v->number, v->ticks, v->ret, v->pstate);
			print_snapshot(m, "pre", &v->before);
			print_snapshot(m, "post", &v->after);
		}
	}
out:
	mutex_unlock(&control_lock);
	return ret;
}
DEFINE_SHOW_ATTRIBUTE(report);

static int counter_show(struct seq_file *m, void *unused)
{
	seq_printf(m, "%llu %llu\n", arch_timer_read_counter(), frequency);
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(counter);

static int __init probe_init(void)
{
	unsigned int cpu;
	int ret;

	if (!is_kernel_in_hyp_mode() ||
	    !of_machine_is_compatible("samsung,galaxy-book4-edge-14"))
		return -ENODEV;
	if (sample_every && !is_power_of_2(sample_every))
		return -EINVAL;
	frequency = read_sysreg(cntfrq_el0);
	if (!frequency)
		return -ENODEV;
	stats = alloc_percpu(struct cpu_stats);
	if (!stats)
		return -ENOMEM;
	for_each_possible_cpu(cpu)
		per_cpu_ptr(stats, cpu)->min_ticks = U64_MAX;
	if (sample_every) {
		gicd = ioremap(GICD_BASE, 0x10000);
		gicr = ioremap(GICR_BASE, NFRAMES * GICR_STRIDE);
		if (!gicd || !gicr) {
			ret = -ENOMEM;
			goto free_maps;
		}
		nwords = min_t(unsigned int,
			       (readl_relaxed(gicd + 4) & 0x1f) + 1, WORDS);
		cpus_read_lock();
		on_each_cpu(find_frame, NULL, 1);
		ret = 0;
		for_each_online_cpu(cpu)
			if (!per_cpu(sgi_base, cpu))
				ret = -ENODEV;
		cpus_read_unlock();
		if (ret)
			goto free_maps;
	}
	smc_probe = (struct kretprobe) {
		.kp.symbol_name = "__invoke_psci_fn_smc",
		.entry_handler = smc_enter,
		.handler = smc_return,
		.maxactive = 4 * num_possible_cpus(),
		.data_size = sizeof(struct call_data),
	};
	loop_probe = (struct kretprobe) {
		.kp.symbol_name = "s2idle_loop",
		.entry_handler = loop_enter,
		.handler = loop_return,
		.maxactive = 2,
	};
	ret = register_kretprobe(&smc_probe);
	if (ret)
		goto free_maps;
	ret = register_kretprobe(&loop_probe);
	if (ret) {
		unregister_kretprobe(&smc_probe);
		goto free_maps;
	}
	running = true;
	debug_dir = debugfs_create_dir("book4_psci_probe", NULL);
	if (IS_ERR_OR_NULL(debug_dir)) {
		ret = debug_dir ? PTR_ERR(debug_dir) : -ENOMEM;
		stop_probe();
		goto free_maps;
	}
	if (IS_ERR_OR_NULL(debugfs_create_file("stop", 0200, debug_dir, NULL, &stop_fops)) ||
	    IS_ERR_OR_NULL(debugfs_create_file("report", 0400, debug_dir, NULL, &report_fops)) ||
	    IS_ERR_OR_NULL(debugfs_create_file("counter", 0400, debug_dir, NULL, &counter_fops))) {
		ret = -ENOMEM;
		debugfs_remove_recursive(debug_dir);
		stop_probe();
		goto free_maps;
	}
	pr_info("psci_probe: EL2/VHE, s2idle-only state=%#x, sample_every=%u\n",
		TARGET_STATE, sample_every);
	return 0;

free_maps:
	if (gicr)
		iounmap(gicr);
	if (gicd)
		iounmap(gicd);
	free_percpu(stats);
	pr_err("psci_probe: initialization failed: %d\n", ret);
	return ret;
}

static void __exit probe_exit(void)
{
	debugfs_remove_recursive(debug_dir);
	mutex_lock(&control_lock);
	stop_probe();
	mutex_unlock(&control_lock);
	if (gicr)
		iounmap(gicr);
	if (gicd)
		iounmap(gicd);
	free_percpu(stats);
}

module_init(probe_init);
module_exit(probe_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Book4 EL2 PSCI SMC boundary timing and sampled wake state");
