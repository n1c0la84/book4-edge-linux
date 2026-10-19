// SPDX-License-Identifier: GPL-2.0-only
/*
 * gic_pending: which interrupts are pending in the GIC when a CPU comes back
 * from a deep idle state (CPU_PM_EXIT)? Reads the CPU's own redistributor
 * (SGIs/PPIs, ISPENDR0) and the distributor (SPIs, GICD_ISPENDRn), counts
 * every pending INTID, and prints the most frequent ones on unload. This
 * includes interrupts Linux never enabled, which firmware may still treat as
 * a reason to abort a power collapse.
 *   insmod gic_pending.ko ; (suspend) ; rmmod gic_pending ; dmesg
 * X1E80100: GICD 0x17000000, GICR 0x17080000, stride 0x40000 (DT).
 */
#include <linux/module.h>
#include <linux/cpu_pm.h>
#include <linux/io.h>
#include <linux/percpu.h>
#include <linux/smp.h>
#include <linux/sort.h>
#include <asm/cputype.h>

#define GICD_BASE	0x17000000
#define GICR_BASE	0x17080000
#define GICR_STRIDE	0x40000
#define NCPU_FRAMES	12
#define MAX_INTID	1024

static void __iomem *gicd, *gicr;
static DEFINE_PER_CPU(void __iomem *, sgi_base);
static bool clear;
module_param(clear, bool, 0444);

static atomic_t hits[MAX_INTID], hits_en[MAX_INTID], hits_entry[MAX_INTID];
static atomic_t entries;
static atomic_t cleared;
static atomic_t exits, exits_none;
static unsigned int nspi_words;

static int notify(struct notifier_block *nb, unsigned long action, void *v)
{
	void __iomem *sgi = this_cpu_read(sgi_base);
	bool any = false;
	unsigned int i, b;
	u32 w, en;

	if (!sgi)
		return NOTIFY_OK;
	if (action == CPU_PM_ENTER) {
		/* what is pending and enabled as the CPU goes down (after clearing) */
		atomic_inc(&entries);
		if (clear) {
			w = readl_relaxed(sgi + 0x200) & ~readl_relaxed(sgi + 0x100);
			if (w) { writel_relaxed(w, sgi + 0x280); atomic_inc(&cleared); }
			for (i = 1; i < nspi_words && i < MAX_INTID / 32; i++) {
				w = readl_relaxed(gicd + 0x200 + 4 * i) & ~readl_relaxed(gicd + 0x100 + 4 * i);
				if (w) { writel_relaxed(w, gicd + 0x280 + 4 * i); atomic_inc(&cleared); }
			}
		}
		w = readl_relaxed(sgi + 0x200) & readl_relaxed(sgi + 0x100);
		for (b = 0; w && b < 32; b++)
			if (w & BIT(b)) atomic_inc(&hits_entry[b]);
		for (i = 1; i < nspi_words && i < MAX_INTID / 32; i++) {
			w = readl_relaxed(gicd + 0x200 + 4 * i);
			if (!w)
				continue;
			w &= readl_relaxed(gicd + 0x100 + 4 * i);
			for (b = 0; w && b < 32; b++)
				if (w & BIT(b)) atomic_inc(&hits_entry[32 * i + b]);
		}
		return NOTIFY_OK;
	}
	if (action != CPU_PM_EXIT)
		return NOTIFY_OK;
	atomic_inc(&exits);
	w = readl_relaxed(sgi + 0x200);			/* GICR_ISPENDR0 */
	en = readl_relaxed(sgi + 0x100);		/* GICR_ISENABLER0 */
	for (b = 0; b < 32; b++)
		if (w & BIT(b)) {
			atomic_inc(&hits[b]); any = true;
			if (en & BIT(b)) atomic_inc(&hits_en[b]);
		}
	for (i = 1; i < nspi_words && i < MAX_INTID / 32; i++) {
		w = readl_relaxed(gicd + 0x200 + 4 * i);	/* GICD_ISPENDRn */
		if (!w)
			continue;
		en = readl_relaxed(gicd + 0x100 + 4 * i);	/* GICD_ISENABLERn */
		for (b = 0; b < 32; b++)
			if (w & BIT(b)) {
				atomic_inc(&hits[32 * i + b]); any = true;
				if (en & BIT(b)) atomic_inc(&hits_en[32 * i + b]);
			}
	}
	if (!any)
		atomic_inc(&exits_none);
	return NOTIFY_OK;
}

static struct notifier_block nb = { .notifier_call = notify };

static void find_frame(void *unused)
{
	u64 mpidr = read_cpuid_mpidr();
	u32 aff = (MPIDR_AFFINITY_LEVEL(mpidr, 3) << 24) | (MPIDR_AFFINITY_LEVEL(mpidr, 2) << 16) |
		  (MPIDR_AFFINITY_LEVEL(mpidr, 1) << 8) | MPIDR_AFFINITY_LEVEL(mpidr, 0);
	int f;

	for (f = 0; f < NCPU_FRAMES; f++) {
		u64 typer = readq_relaxed(gicr + f * GICR_STRIDE + 0x8);
		if ((typer >> 32) == aff) {
			this_cpu_write(sgi_base, gicr + f * GICR_STRIDE + 0x10000);
			return;
		}
	}
	pr_warn("gic_pending: cpu%d: no redistributor frame for aff %08x\n", smp_processor_id(), aff);
}

static int __init gic_pending_init(void)
{
	gicd = ioremap(GICD_BASE, 0x10000);
	gicr = ioremap(GICR_BASE, NCPU_FRAMES * GICR_STRIDE);
	if (!gicd || !gicr)
		return -ENOMEM;
	nspi_words = (readl_relaxed(gicd + 0x4) & 0x1f) + 1;	/* GICD_TYPER.ITLinesNumber */
	on_each_cpu(find_frame, NULL, 1);
	cpu_pm_register_notifier(&nb);
	pr_info("gic_pending: watching CPU_PM_EXIT, %u interrupt words\n", nspi_words);
	return 0;
}

struct ent { int id, n; };
static int cmp(const void *a, const void *b) { return ((const struct ent *)b)->n - ((const struct ent *)a)->n; }
static struct ent ents[MAX_INTID];

static void __exit gic_pending_exit(void)
{
	int i, n = 0;

	cpu_pm_unregister_notifier(&nb);
	for (i = 0; i < MAX_INTID; i++)
		if (atomic_read(&hits_entry[i]))
			pr_info("gic_pending:   at CPU_PM_ENTER (%d): INTID %d pending+enabled %d times\n",
				atomic_read(&entries), i, atomic_read(&hits_entry[i]));
	for (i = 0; i < MAX_INTID; i++)
		if (atomic_read(&hits[i]))
			ents[n++] = (struct ent){ i, atomic_read(&hits[i]) };
	sort(ents, n, sizeof(ents[0]), cmp, NULL);
	pr_info("gic_pending: %d CPU_PM exits, %d with nothing pending%s, %d clearing writes\n",
		atomic_read(&exits), atomic_read(&exits_none), clear ? " (clear=1)" : "",
		atomic_read(&cleared));
	for (i = 0; i < n && i < 20; i++)
		pr_info("gic_pending:   INTID %4d (%s %d) pending at %d exits, enabled at %d\n", ents[i].id,
			ents[i].id < 16 ? "SGI" : ents[i].id < 32 ? "PPI" : "SPI",
			ents[i].id < 32 ? ents[i].id : ents[i].id - 32, ents[i].n,
			atomic_read(&hits_en[ents[i].id]));
	iounmap(gicr);
	iounmap(gicd);
}

module_init(gic_pending_init);
module_exit(gic_pending_exit);
MODULE_DESCRIPTION("Count GIC interrupts pending at CPU_PM_EXIT (debugging)");
MODULE_LICENSE("GPL");
