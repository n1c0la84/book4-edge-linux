// SPDX-License-Identifier: GPL-2.0-only
/*
 * spss_check: is the Secure Processor (SPSS, ACPI QCOM0C8D, booted by UEFI
 * with RSPU.bin) running and sleeping? Prints the SMEM subsystem sleep stats
 * (item 605) of every host that has them, and whether TrustZone manages
 * SPSS as a PAS image (PAS ID 14, as in Qualcomm's downstream DTs).
 * Hosts without a private partition fall back to the global items, so only
 * items that differ from the global ones are printed for a host.
 *   insmod spss_check.ko [shutdown=1] ; dmesg | grep spss_check ; rmmod spss_check
 * Read-only unless shutdown=1, which asks TrustZone to stop SPSS
 * (qcom_scm_pas_shutdown(14), as remoteproc does for the DSPs). A reboot
 * starts it again (UEFI loads it).
 */
#include <linux/module.h>
#include <linux/err.h>
#include <linux/soc/qcom/smem.h>
#include <linux/firmware/qcom/qcom_scm.h>

#ifndef QCOM_SMEM_HOST_ANY
#define QCOM_SMEM_HOST_ANY	-1
#endif
#define SPSS_PAS_ID		14

static bool shutdown;
module_param(shutdown, bool, 0444);

struct sleep_stats {
	u32 stat_type;
	u32 count;
	u64 last_entered_at;
	u64 last_exited_at;
	u64 accumulated;
};

static const char * const hosts[] = {
	"apps", "modem", "adsp", "slpi", "wcnss", "cdsp", "rpm", "tz",
	"spss", "hyp", "npu", "spss_sp", "nsp1", "wpss", "tme", "apps2",
};

static int __init spss_check_init(void)
{
	int pid;		/* -1 = QCOM_SMEM_HOST_ANY (global items) */

	unsigned int item;

	for (pid = -1; pid < 20; pid++)
		for (item = 600; item <= 640; item++) {
			struct sleep_stats *s;
			size_t sz;

			s = qcom_smem_get(pid, item, &sz);
			if (IS_ERR(s) || sz < sizeof(*s))
				continue;
			if (pid >= 0 && s == qcom_smem_get(QCOM_SMEM_HOST_ANY, item, NULL))
				continue;	/* fell back to the global item */
			pr_info("spss_check: host %2d %-8s item %u: type %#x count %u, last entered %llu exited %llu, accumulated %llu (%zu bytes)\n",
				pid, pid < 0 ? "global" : pid < (int)ARRAY_SIZE(hosts) ? hosts[pid] : "?", item,
				s->stat_type, s->count, s->last_entered_at,
				s->last_exited_at, s->accumulated, sz);
		}
	pr_info("spss_check: SCM available %d, PAS %d supported %d\n",
		qcom_scm_is_available(), SPSS_PAS_ID,
		qcom_scm_is_available() ? qcom_scm_pas_supported(SPSS_PAS_ID) : -1);
	if (shutdown)
		pr_info("spss_check: qcom_scm_pas_shutdown(%d) = %d\n", SPSS_PAS_ID,
			qcom_scm_pas_shutdown(SPSS_PAS_ID));
	return 0;
}

static void __exit spss_check_exit(void) { }

module_init(spss_check_init);
module_exit(spss_check_exit);
MODULE_DESCRIPTION("Secure Processor sleep stats from SMEM (debugging)");
MODULE_LICENSE("GPL");
