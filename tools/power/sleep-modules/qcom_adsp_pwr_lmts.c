// SPDX-License-Identifier: GPL-2.0
/*
 * Based on github.com/justririll/x1e-sleep (commit 4e84b60); changed for the
 * Galaxy Book4 Edge: the message is sent from a PM notifier, not from the
 * rpmsg device's suspend callback.
 */
/*
 * Tell the ADSP when the system enters and leaves sleep, like Windows does.
 *
 * Windows' PEP (qcpep8380.sys) sends a MODERN_STANDBY_STATE message on the
 * APPS_ADSP_PWR_LMTS_GLINK_PORT channel when the platform enters Modern
 * Standby (state 1) and when it leaves it (state 0). On entry the ADSP stops
 * its power-limits (PLD) timer, which otherwise wakes it ~100 times per
 * second.
 *
 * Message, as built by qcpep8380.sys FUN_1400ebb00 (24 bytes):
 *   { size 0x18, type 1, count 1, state, 0, 0 }
 * (type 0 on the same channel carries power-limit values, FUN_1400ec2a8.)
 *
 * When: the PEP sends it on the Modern Standby _DSM notification "MSBN"
 * phase 7 (entry) / phase 8 (exit) (FUN_140455210), i.e. at the start of
 * standby while every device is still active. Sent from the rpmsg device's
 * suspend callback instead (late in system suspend, LPASS already
 * suspended), it crashed the Book4's ADSP at every suspend ("fatal error
 * received: EX:kernel:0x1:ipcc_irq121"). So send it from a PM notifier:
 * PM_SUSPEND_PREPARE runs before tasks are frozen and devices suspended,
 * PM_POST_SUSPEND after everything has resumed.
 */
#include <linux/module.h>
#include <linux/mod_devicetable.h>
#include <linux/mutex.h>
#include <linux/rpmsg.h>
#include <linux/suspend.h>

#define PWR_LMTS_MODERN_STANDBY_STATE	1

struct pwr_lmts_msg {
	__le32 size;
	__le32 type;
	__le32 count;
	__le32 state;
	__le32 reserved[2];
} __packed;

static DEFINE_MUTEX(pwr_lmts_lock);
static struct rpmsg_device *pwr_lmts_rpdev;

static int pwr_lmts_send_state(struct rpmsg_device *rpdev, u32 state)
{
	struct pwr_lmts_msg msg = {
		.size = cpu_to_le32(sizeof(msg)),
		.type = cpu_to_le32(PWR_LMTS_MODERN_STANDBY_STATE),
		.count = cpu_to_le32(1),
		.state = cpu_to_le32(state),
	};
	int ret;

	ret = rpmsg_send(rpdev->ept, &msg, sizeof(msg));
	if (ret)
		dev_warn(&rpdev->dev, "failed to send standby state %u: %d\n", state, ret);
	else
		dev_dbg(&rpdev->dev, "standby state %u sent\n", state);
	return ret;
}

static int pwr_lmts_pm_notify(struct notifier_block *nb, unsigned long action, void *data)
{
	u32 state;

	switch (action) {
	case PM_SUSPEND_PREPARE:
		state = 1;
		break;
	case PM_POST_SUSPEND:
		state = 0;
		break;
	default:
		return NOTIFY_DONE;
	}
	mutex_lock(&pwr_lmts_lock);
	/* Do not block suspend if the ADSP does not take the message */
	if (pwr_lmts_rpdev)
		pwr_lmts_send_state(pwr_lmts_rpdev, state);
	mutex_unlock(&pwr_lmts_lock);
	return NOTIFY_DONE;
}

static struct notifier_block pwr_lmts_pm_nb = { .notifier_call = pwr_lmts_pm_notify };

static int pwr_lmts_callback(struct rpmsg_device *rpdev, void *data, int len,
			     void *priv, u32 addr)
{
	dev_dbg(&rpdev->dev, "rx %d bytes\n", len);
	return 0;
}

static int pwr_lmts_probe(struct rpmsg_device *rpdev)
{
	mutex_lock(&pwr_lmts_lock);
	pwr_lmts_rpdev = rpdev;
	mutex_unlock(&pwr_lmts_lock);
	dev_info(&rpdev->dev, "Modern Standby notifications on suspend/resume\n");
	return 0;
}

static void pwr_lmts_remove(struct rpmsg_device *rpdev)
{
	mutex_lock(&pwr_lmts_lock);
	if (pwr_lmts_rpdev == rpdev)
		pwr_lmts_rpdev = NULL;
	mutex_unlock(&pwr_lmts_lock);
}

static const struct rpmsg_device_id pwr_lmts_id_table[] = {
	{ .name = "APPS_ADSP_PWR_LMTS_GLINK_PORT" },
	{ }
};
MODULE_DEVICE_TABLE(rpmsg, pwr_lmts_id_table);

static struct rpmsg_driver pwr_lmts_driver = {
	.drv.name = "qcom_adsp_pwr_lmts",
	.id_table = pwr_lmts_id_table,
	.probe = pwr_lmts_probe,
	.remove = pwr_lmts_remove,
	.callback = pwr_lmts_callback,
};

static int __init pwr_lmts_init(void)
{
	int ret = register_pm_notifier(&pwr_lmts_pm_nb);

	if (ret)
		return ret;
	ret = register_rpmsg_driver(&pwr_lmts_driver);
	if (ret)
		unregister_pm_notifier(&pwr_lmts_pm_nb);
	return ret;
}

static void __exit pwr_lmts_exit(void)
{
	unregister_rpmsg_driver(&pwr_lmts_driver);
	unregister_pm_notifier(&pwr_lmts_pm_nb);
}

module_init(pwr_lmts_init);
module_exit(pwr_lmts_exit);
MODULE_DESCRIPTION("Qualcomm ADSP power-limits Modern Standby notification");
MODULE_LICENSE("GPL");
