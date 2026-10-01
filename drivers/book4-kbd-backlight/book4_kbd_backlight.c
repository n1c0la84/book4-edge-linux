// SPDX-License-Identifier: GPL-2.0-only
/*
 * Samsung Galaxy Book4 Edge keyboard backlight.
 *
 * The ENE KB9058 EC takes the command {0x10, timeout, level} as a plain I2C
 * write on its "raw" target (ACPI ECTC: 0x62 on \_SB.I2C6). Found in the
 * Windows EC2.sys driver (IOCTL_SET_KBDBLT, logged as "timeout" and "Level").
 * Tested on the 14" (NP940XMA):
 *   level   0 = off, 1..3 = brighter (higher values act as 3)
 *   timeout labelled so in EC2.sys, but the EC turns the light off about 3 s
 *           after every command whatever its value (timed with 10 and 11;
 *           0, 5 and 255 behaved alike)
 * The EC neither relights on key presses nor keeps the light on, so this
 * driver implements the idle timeout itself: on keyboard activity it lights
 * the backlight and then refreshes it every 2 s until idle_timeout seconds
 * have passed without a key press.
 */

#include <linux/i2c.h>
#include <linux/input.h>
#include <linux/jiffies.h>
#include <linux/leds.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/slab.h>
#include <linux/workqueue.h>

#define KBDBLT_CMD		0x10
#define KBDBLT_MAX_LEVEL	3
#define KBDBLT_REFRESH_MS	2000	/* below the EC's ~3 s auto-off */

static unsigned int idle_timeout = 30;
module_param(idle_timeout, uint, 0644);
MODULE_PARM_DESC(idle_timeout,
		 "Seconds without key presses before the backlight turns off (0 = always on, default 30)");

/*
 * Second byte of the EC command ("timeout" in EC2.sys). Its effect is not
 * understood: 30 held steady in the first version (resent on key presses),
 * 255 with refreshes every 2 s made the light
 * blink. Writable at runtime for experiments.
 */
static unsigned int ec_timeout = 30;
module_param(ec_timeout, uint, 0644);
MODULE_PARM_DESC(ec_timeout, "Second byte of the EC backlight command (default 30)");

struct book4_kbd {
	struct i2c_client *client;
	struct led_classdev led;
	struct input_handler handler;
	struct work_struct relight;
	struct delayed_work refresh;
	struct mutex lock;		/* serialises EC writes and state */
	unsigned int level;
	unsigned long last_sent;	/* jiffies of the last EC write */
	unsigned long last_activity;	/* jiffies of the last key press */
};

static int book4_kbd_send(struct book4_kbd *kbd)
{
	u8 buf[3] = { KBDBLT_CMD, min(READ_ONCE(ec_timeout), 255U), kbd->level };
	int ret;

	lockdep_assert_held(&kbd->lock);

	ret = i2c_master_send(kbd->client, buf, sizeof(buf));
	if (ret < 0)
		return ret;
	if (ret != sizeof(buf))
		return -EIO;
	kbd->last_sent = jiffies;
	return 0;
}

/* Still within the idle window? (idle_timeout 0 = always on) */
static bool book4_kbd_active(struct book4_kbd *kbd)
{
	unsigned int timeout = READ_ONCE(idle_timeout);

	if (!kbd->level)
		return false;
	return !timeout ||
	       time_before(jiffies, kbd->last_activity + timeout * HZ);
}

/* Light now and keep refreshing until the idle window closes. */
static int book4_kbd_light(struct book4_kbd *kbd)
{
	int ret;

	lockdep_assert_held(&kbd->lock);

	ret = book4_kbd_send(kbd);
	if (!ret && kbd->level)
		mod_delayed_work(system_wq, &kbd->refresh,
				 msecs_to_jiffies(KBDBLT_REFRESH_MS));
	return ret;
}

static int book4_kbd_set(struct led_classdev *led, enum led_brightness value)
{
	struct book4_kbd *kbd = container_of(led, struct book4_kbd, led);

	guard(mutex)(&kbd->lock);
	kbd->level = min_t(unsigned int, value, KBDBLT_MAX_LEVEL);
	kbd->last_activity = jiffies;	/* show the new level */
	return book4_kbd_light(kbd);
}

static enum led_brightness book4_kbd_get(struct led_classdev *led)
{
	struct book4_kbd *kbd = container_of(led, struct book4_kbd, led);

	return READ_ONCE(kbd->level);
}

static void book4_kbd_relight_work(struct work_struct *work)
{
	struct book4_kbd *kbd = container_of(work, struct book4_kbd, relight);
	int ret;

	guard(mutex)(&kbd->lock);
	if (!kbd->level)
		return;
	ret = book4_kbd_light(kbd);
	if (ret)
		dev_warn_ratelimited(&kbd->client->dev, "relight failed: %d\n", ret);
}

static void book4_kbd_refresh_work(struct work_struct *work)
{
	struct book4_kbd *kbd = container_of(to_delayed_work(work),
					     struct book4_kbd, refresh);

	guard(mutex)(&kbd->lock);
	if (book4_kbd_active(kbd) && book4_kbd_light(kbd))
		dev_warn_ratelimited(&kbd->client->dev, "refresh failed\n");
	/* otherwise stop: the EC turns the light off ~3 s after the last write */
}

/* Input events arrive in atomic context: only queue the I2C write. */
static void book4_kbd_input_event(struct input_handle *handle, unsigned int type,
				  unsigned int code, int value)
{
	struct book4_kbd *kbd = handle->handler->private;

	if (type != EV_KEY || value != 1 || !READ_ONCE(kbd->level))
		return;
	WRITE_ONCE(kbd->last_activity, jiffies);
	/* While refreshing, the refresh work keeps it lit; else light it now. */
	if (time_before(jiffies, READ_ONCE(kbd->last_sent) + HZ))
		return;
	if (!delayed_work_pending(&kbd->refresh))
		schedule_work(&kbd->relight);
}

static int book4_kbd_input_connect(struct input_handler *handler,
				   struct input_dev *dev,
				   const struct input_device_id *id)
{
	struct input_handle *handle;
	int ret;

	handle = kzalloc(sizeof(*handle), GFP_KERNEL);
	if (!handle)
		return -ENOMEM;

	handle->dev = dev;
	handle->handler = handler;
	handle->name = "book4-kbd-backlight";

	ret = input_register_handle(handle);
	if (ret)
		goto err_free;
	ret = input_open_device(handle);
	if (ret)
		goto err_unregister;
	return 0;

err_unregister:
	input_unregister_handle(handle);
err_free:
	kfree(handle);
	return ret;
}

static void book4_kbd_input_disconnect(struct input_handle *handle)
{
	input_close_device(handle);
	input_unregister_handle(handle);
	kfree(handle);
}

/* Any device with letter keys counts as a keyboard. */
static const struct input_device_id book4_kbd_input_ids[] = {
	{
		.flags = INPUT_DEVICE_ID_MATCH_EVBIT | INPUT_DEVICE_ID_MATCH_KEYBIT,
		.evbit = { BIT_MASK(EV_KEY) },
		.keybit = { [BIT_WORD(KEY_A)] = BIT_MASK(KEY_A) },
	},
	{ }
};

static int book4_kbd_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct book4_kbd *kbd;
	int ret;

	kbd = devm_kzalloc(dev, sizeof(*kbd), GFP_KERNEL);
	if (!kbd)
		return -ENOMEM;

	kbd->client = client;
	mutex_init(&kbd->lock);
	INIT_WORK(&kbd->relight, book4_kbd_relight_work);
	INIT_DELAYED_WORK(&kbd->refresh, book4_kbd_refresh_work);
	i2c_set_clientdata(client, kbd);

	/* Start dark; systemd-backlight restores the saved level. */
	scoped_guard(mutex, &kbd->lock)
		ret = book4_kbd_send(kbd);
	if (ret)
		return dev_err_probe(dev, ret, "EC not answering at 0x%02x\n",
				     client->addr);

	kbd->led.name = "samsung::kbd_backlight";
	kbd->led.max_brightness = KBDBLT_MAX_LEVEL;
	kbd->led.brightness_set_blocking = book4_kbd_set;
	kbd->led.brightness_get = book4_kbd_get;
	kbd->led.flags = LED_CORE_SUSPENDRESUME;
	ret = devm_led_classdev_register(dev, &kbd->led);
	if (ret)
		return ret;

	kbd->handler.event = book4_kbd_input_event;
	kbd->handler.connect = book4_kbd_input_connect;
	kbd->handler.disconnect = book4_kbd_input_disconnect;
	kbd->handler.name = "book4_kbd_backlight";
	kbd->handler.id_table = book4_kbd_input_ids;
	kbd->handler.private = kbd;
	ret = input_register_handler(&kbd->handler);
	if (ret)
		return ret;

	return 0;
}

static void book4_kbd_remove(struct i2c_client *client)
{
	struct book4_kbd *kbd = i2c_get_clientdata(client);

	input_unregister_handler(&kbd->handler);
	cancel_work_sync(&kbd->relight);
	cancel_delayed_work_sync(&kbd->refresh);
}

static const struct i2c_device_id book4_kbd_id[] = {
	{ "book4-kbd-backlight" },
	{ }
};
MODULE_DEVICE_TABLE(i2c, book4_kbd_id);

static struct i2c_driver book4_kbd_driver = {
	.driver = {
		.name = "book4-kbd-backlight",
	},
	.probe = book4_kbd_probe,
	.remove = book4_kbd_remove,
	.id_table = book4_kbd_id,
};
module_i2c_driver(book4_kbd_driver);

MODULE_DESCRIPTION("Samsung Galaxy Book4 Edge keyboard backlight");
MODULE_LICENSE("GPL");
