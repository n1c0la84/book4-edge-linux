// SPDX-License-Identifier: GPL-2.0-only
/*
 * book4_dsp_sleepstate: tell the ADSP and CDSP when the CPUs go to sleep, as
 * Windows does, through an outbound SMP2P entry named "sleepstate".
 *
 * Windows' subsystem driver (qcsubsys8380.sys) opens a "sleepstate" SMP2P
 * entry towards each subsystem (FUN_1400a4a80) and, on the PEP's
 * \Callback\QcModernStandby notification, writes 0 on Modern Standby entry
 * (FUN_14001eb50) and 0x1000 on exit (FUN_14001eef0); 0x1000 (bit 12) means
 * "APSS awake". The PEP fires that callback independently of
 * EnablePowerLimitsInterface, so unlike the ADSP power-limits message it is
 * sent on the Book4 too. Without the entry the DSPs keep CX up in s2idle.
 * Based on asus_adsp_sleepstate from github.com/justririll/x1e-sleep, for
 * both DSPs, with the value and polarity confirmed from qcsubsys8380.sys.
 *
 * DT (dts/src/x1-el2-book4.dtso): outbound "sleepstate" entries in
 * smp2p-adsp and smp2p-cdsp, and a node
 *   compatible = "book4,dsp-sleepstate";
 *   qcom,smem-states = <&adsp_entry 0>, <&cdsp_entry 0>;
 *   qcom,smem-state-names = "adsp", "cdsp";
 *
 * Written at probe (awake), PM_SUSPEND_PREPARE (asleep) and PM_POST_SUSPEND
 * (awake). Manual: echo 0|1 > /sys/module/book4_dsp_sleepstate/parameters/awake
 */
#include <linux/module.h>
#include <linux/mod_devicetable.h>
#include <linux/mutex.h>
#include <linux/platform_device.h>
#include <linux/soc/qcom/smem_state.h>
#include <linux/suspend.h>

#define SLEEPSTATE_AWAKE	0x1000		/* bit 12 */
#define SLEEPSTATE_MASK		0xffffffffu

static const char * const names[] = { "adsp", "cdsp" };

struct dsp_ss {
	struct device *dev;
	struct qcom_smem_state *state[ARRAY_SIZE(names)];
	struct notifier_block nb;
	bool awake;
};

static DEFINE_MUTEX(dsp_ss_lock);
static struct dsp_ss *g_ss;

static void ss_write(struct dsp_ss *s, bool awake)
{
	int i, ret;

	for (i = 0; i < ARRAY_SIZE(names); i++) {
		if (!s->state[i])
			continue;
		ret = qcom_smem_state_update_bits(s->state[i], SLEEPSTATE_MASK,
						  awake ? SLEEPSTATE_AWAKE : 0);
		if (ret)
			dev_warn(s->dev, "%s sleepstate: write failed: %d\n", names[i], ret);
	}
	s->awake = awake;
	dev_dbg(s->dev, "sleepstate %s\n", awake ? "awake (0x1000)" : "asleep (0)");
}

static int ss_pm_notify(struct notifier_block *nb, unsigned long ev, void *unused)
{
	struct dsp_ss *s = container_of(nb, struct dsp_ss, nb);

	mutex_lock(&dsp_ss_lock);
	if (ev == PM_SUSPEND_PREPARE)
		ss_write(s, false);
	else if (ev == PM_POST_SUSPEND)
		ss_write(s, true);
	mutex_unlock(&dsp_ss_lock);
	return NOTIFY_DONE;
}

static int awake_set(const char *val, const struct kernel_param *kp)
{
	bool v;
	int ret = kstrtobool(val, &v);

	if (ret)
		return ret;
	mutex_lock(&dsp_ss_lock);
	if (g_ss)
		ss_write(g_ss, v);
	else
		ret = -ENODEV;
	mutex_unlock(&dsp_ss_lock);
	return ret;
}

static int awake_get(char *buf, const struct kernel_param *kp)
{
	return sysfs_emit(buf, "%d\n", g_ss ? g_ss->awake : -1);
}

static const struct kernel_param_ops awake_ops = { .set = awake_set, .get = awake_get };
module_param_cb(awake, &awake_ops, NULL, 0644);
MODULE_PARM_DESC(awake, "Write the DSP sleepstate entries (1 = APSS awake 0x1000, 0 = asleep)");

static int ss_probe(struct platform_device *pdev)
{
	struct dsp_ss *s;
	unsigned int bit;
	int i, n = 0, ret;

	s = devm_kzalloc(&pdev->dev, sizeof(*s), GFP_KERNEL);
	if (!s)
		return -ENOMEM;
	s->dev = &pdev->dev;
	for (i = 0; i < ARRAY_SIZE(names); i++) {
		struct qcom_smem_state *st = qcom_smem_state_get(&pdev->dev, names[i], &bit);

		if (IS_ERR(st)) {
			if (PTR_ERR(st) == -EPROBE_DEFER)
				goto defer;
			dev_warn(&pdev->dev, "no %s sleepstate entry: %ld\n", names[i], PTR_ERR(st));
			continue;
		}
		s->state[i] = st;
		n++;
	}
	if (!n)
		return -ENODEV;

	s->nb.notifier_call = ss_pm_notify;
	ret = register_pm_notifier(&s->nb);
	if (ret)
		goto put;
	platform_set_drvdata(pdev, s);
	mutex_lock(&dsp_ss_lock);
	g_ss = s;
	ss_write(s, true);	/* Windows writes 0x1000 once the subsystem is up */
	mutex_unlock(&dsp_ss_lock);
	dev_info(&pdev->dev, "sleepstate for %s%s%s\n", s->state[0] ? "adsp" : "",
		 s->state[0] && s->state[1] ? " and " : "", s->state[1] ? "cdsp" : "");
	return 0;

defer:
	ret = -EPROBE_DEFER;
put:
	for (i = 0; i < ARRAY_SIZE(names); i++)
		if (s->state[i])
			qcom_smem_state_put(s->state[i]);
	return ret;
}

static void ss_remove(struct platform_device *pdev)
{
	struct dsp_ss *s = platform_get_drvdata(pdev);
	int i;

	mutex_lock(&dsp_ss_lock);
	g_ss = NULL;
	mutex_unlock(&dsp_ss_lock);
	unregister_pm_notifier(&s->nb);
	for (i = 0; i < ARRAY_SIZE(names); i++)
		if (s->state[i])
			qcom_smem_state_put(s->state[i]);
}

static const struct of_device_id ss_of_match[] = {
	{ .compatible = "book4,dsp-sleepstate" },
	{ }
};
MODULE_DEVICE_TABLE(of, ss_of_match);

static struct platform_driver ss_driver = {
	.probe = ss_probe,
	.remove = ss_remove,
	.driver = {
		.name = "book4-dsp-sleepstate",
		.of_match_table = ss_of_match,
	},
};
module_platform_driver(ss_driver);

MODULE_DESCRIPTION("DSP SMP2P sleepstate (Windows qcsubsys Modern Standby behaviour)");
MODULE_LICENSE("GPL");
