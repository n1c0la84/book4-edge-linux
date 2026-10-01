// SPDX-License-Identifier: GPL-2.0-only
/*
 * Samsung Galaxy Book4 Edge embedded controller (ENE KB9058, ACPI SAM060B):
 * battery and AC adapter.
 *
 * The EC sits at 0x64 on the same I2C bus as its HID keyboard function (0x05).
 * Protocol, reverse-engineered from the Windows EC2.sys driver:
 *
 *   XDATA read : write {0x30, 0x00, hi, lo}, repeated-start read 2 -> {0x50, val}
 *   XDATA write: write {0x40, 0x00, hi, lo, val}
 *
 * The ACPI "EcSpace" (region 0xA1) is reached through a mailbox in XDATA:
 *   0xFF10 command (0x88 read, 0x89 write; reads 0 when idle)
 *   0xF480 offset in, read result out
 *   0xF49F slot bitmap, 0xF49E collision bitmap (shared with the EC firmware)
 *
 * EC-space battery fields are big-endian u16s:
 *   0x80 bit0 battery present, bit2 AC online
 *   0x84 state: bit0 discharging, bit1 charging (ACPI _BST)
 *   0xA0 capacity %          0xA2 remaining mAh
 *   0xA4 rate mA (unsigned)  0xA6 voltage mV
 *   0xB0 design mAh          0xB2 last full mAh
 *   0xB4 design voltage mV
 */

#include <linux/bits.h>
#include <linux/cleanup.h>
#include <linux/delay.h>
#include <linux/devm-helpers.h>
#include <linux/i2c.h>
#include <linux/jiffies.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/power_supply.h>
#include <linux/unaligned.h>

#define XDATA_CMD		0xff10
#define XDATA_OFFSET		0xf480
#define XDATA_SLOTS		0xf49f
#define XDATA_COLLISIONS	0xf49e

#define EC_CMD_READ		0x88
#define XDATA_READ_OK		0x50

#define EC_FLAGS		0x80
#define EC_FLAG_BAT_PRESENT	BIT(0)
#define EC_FLAG_AC_ONLINE	BIT(2)
#define EC_BAT_STATE		0x84
#define EC_STATE_DISCHARGING	BIT(0)
#define EC_STATE_CHARGING	BIT(1)
#define EC_BAT_DYNAMIC		0xa0	/* 8 bytes: capacity, remaining, rate, voltage */
#define EC_BAT_STATIC		0xb0	/* 6 bytes: design, last full, design voltage */
#define EC_BAT_MODEL		0xe0	/* NUL-terminated ASCII, e.g. "4474D35" */
#define EC_BAT_MODEL_LEN	8

#define EC_UNKNOWN		0xffff	/* ACPI _BST sentinel for "not available" */

#define CACHE_MS		2000
#define POLL_MS			10000

struct book4_ec {
	struct i2c_client *client;
	struct mutex lock;		/* serialises mailbox use and the cache */
	struct power_supply *bat;
	struct power_supply *ac;
	struct delayed_work poll;
	unsigned long updated;		/* jiffies of last successful read */
	bool valid;

	u8 flags, state;
	u16 capacity, remaining, rate, voltage;
	u16 design, full, design_mv;
	char model[EC_BAT_MODEL_LEN + 1];
};

static int xdata_read(struct book4_ec *ec, u16 addr, u8 *val)
{
	u8 tx[4] = { 0x30, 0x00, addr >> 8, addr & 0xff };
	u8 rx[2];
	struct i2c_msg msgs[] = {
		{ .addr = ec->client->addr, .len = sizeof(tx), .buf = tx },
		{ .addr = ec->client->addr, .flags = I2C_M_RD, .len = sizeof(rx), .buf = rx },
	};
	int ret;

	ret = i2c_transfer(ec->client->adapter, msgs, ARRAY_SIZE(msgs));
	if (ret < 0)
		return ret;
	if (ret != ARRAY_SIZE(msgs))
		return -EIO;
	if (rx[0] != XDATA_READ_OK)
		return -EPROTO;
	*val = rx[1];
	return 0;
}

static int xdata_write(struct book4_ec *ec, u16 addr, u8 val)
{
	u8 tx[5] = { 0x40, 0x00, addr >> 8, addr & 0xff, val };
	int ret;

	ret = i2c_master_send(ec->client, tx, sizeof(tx));
	if (ret < 0)
		return ret;
	return ret == sizeof(tx) ? 0 : -EIO;
}

static int mbox_wait_idle(struct book4_ec *ec)
{
	u8 cmd;
	int i, ret;

	for (i = 0; i <= 30; i++) {
		ret = xdata_read(ec, XDATA_CMD, &cmd);
		if (ret)
			return ret;
		if (!cmd)
			return 0;
		usleep_range(1000, 1500);
	}
	return -EBUSY;
}

static int mbox_get_slot(struct book4_ec *ec)
{
	u8 used, coll;
	int slot, ret;

	ret = xdata_read(ec, XDATA_SLOTS, &used);
	if (ret)
		return ret;
	ret = xdata_read(ec, XDATA_COLLISIONS, &coll);
	if (ret)
		return ret;
	if (coll != used) {
		ret = xdata_write(ec, XDATA_COLLISIONS, used);
		if (ret)
			return ret;
	}
	slot = ffz(used);
	if (slot >= 8)
		return -EBUSY;
	ret = xdata_write(ec, XDATA_SLOTS, used | BIT(slot));
	return ret ?: slot;
}

static int mbox_put_slot(struct book4_ec *ec, int slot, bool *collided)
{
	u8 used, coll;
	int ret;

	ret = xdata_read(ec, XDATA_COLLISIONS, &coll);
	if (ret)
		return ret;
	*collided = coll & BIT(slot);
	ret = xdata_read(ec, XDATA_SLOTS, &used);
	if (ret)
		return ret;
	ret = xdata_write(ec, XDATA_SLOTS, used & ~BIT(slot));
	if (ret)
		return ret;
	return xdata_write(ec, XDATA_COLLISIONS, coll & ~BIT(slot));
}

static int ec_read_byte(struct book4_ec *ec, u8 offset, u8 *val)
{
	bool collided;
	int slot, try, ret;

	for (try = 0; try < 5; try++) {
		ret = mbox_wait_idle(ec);
		if (ret)
			return ret;
		slot = mbox_get_slot(ec);
		if (slot < 0)
			return slot;

		ret = xdata_write(ec, XDATA_OFFSET, offset);
		if (!ret)
			ret = xdata_write(ec, XDATA_CMD, EC_CMD_READ);
		if (!ret)
			ret = mbox_wait_idle(ec);
		if (!ret)
			ret = xdata_read(ec, XDATA_OFFSET, val);

		/* Always release the slot, even after an error. */
		if (mbox_put_slot(ec, slot, &collided) && !ret)
			ret = -EIO;
		if (ret)
			return ret;
		if (!collided)
			return 0;
	}
	return -EAGAIN;
}

static int ec_read_block(struct book4_ec *ec, u8 offset, u8 *buf, int len)
{
	int i, ret;

	for (i = 0; i < len; i++) {
		ret = ec_read_byte(ec, offset + i, &buf[i]);
		if (ret)
			return ret;
	}
	return 0;
}

static int book4_ec_update(struct book4_ec *ec)
{
	u8 dyn[8], stat[6];
	int ret;

	lockdep_assert_held(&ec->lock);

	if (ec->valid && time_before(jiffies, ec->updated + msecs_to_jiffies(CACHE_MS)))
		return 0;

	ret = ec_read_byte(ec, EC_FLAGS, &ec->flags);
	if (!ret)
		ret = ec_read_byte(ec, EC_BAT_STATE, &ec->state);
	if (!ret)
		ret = ec_read_block(ec, EC_BAT_DYNAMIC, dyn, sizeof(dyn));
	if (!ret && !ec->valid)		/* design values never change */
		ret = ec_read_block(ec, EC_BAT_STATIC, stat, sizeof(stat));
	if (!ret && !ec->valid)
		ret = ec_read_block(ec, EC_BAT_MODEL, (u8 *)ec->model, EC_BAT_MODEL_LEN);
	if (ret) {
		dev_warn_ratelimited(&ec->client->dev, "EC read failed: %d\n", ret);
		return ret;
	}

	ec->capacity  = get_unaligned_be16(&dyn[0]);
	ec->remaining = get_unaligned_be16(&dyn[2]);
	ec->rate      = get_unaligned_be16(&dyn[4]);
	ec->voltage   = get_unaligned_be16(&dyn[6]);
	if (!ec->valid) {
		ec->design    = get_unaligned_be16(&stat[0]);
		ec->full      = get_unaligned_be16(&stat[2]);
		ec->design_mv = get_unaligned_be16(&stat[4]);
	}
	ec->updated = jiffies;
	ec->valid = true;
	return 0;
}

static int book4_bat_status(struct book4_ec *ec)
{
	if (ec->state & EC_STATE_CHARGING)
		return POWER_SUPPLY_STATUS_CHARGING;
	if (ec->state & EC_STATE_DISCHARGING)
		return POWER_SUPPLY_STATUS_DISCHARGING;
	if (!(ec->flags & EC_FLAG_AC_ONLINE))
		return POWER_SUPPLY_STATUS_DISCHARGING;
	if (ec->capacity == 100)
		return POWER_SUPPLY_STATUS_FULL;
	return POWER_SUPPLY_STATUS_NOT_CHARGING;
}

static const enum power_supply_property book4_bat_props[] = {
	POWER_SUPPLY_PROP_STATUS,
	POWER_SUPPLY_PROP_PRESENT,
	POWER_SUPPLY_PROP_TECHNOLOGY,
	POWER_SUPPLY_PROP_CAPACITY,
	POWER_SUPPLY_PROP_CHARGE_NOW,
	POWER_SUPPLY_PROP_CHARGE_FULL,
	POWER_SUPPLY_PROP_CHARGE_FULL_DESIGN,
	POWER_SUPPLY_PROP_CURRENT_NOW,
	POWER_SUPPLY_PROP_VOLTAGE_NOW,
	POWER_SUPPLY_PROP_VOLTAGE_MIN_DESIGN,
	POWER_SUPPLY_PROP_MODEL_NAME,
	POWER_SUPPLY_PROP_MANUFACTURER,
};

/* Scale an EC value to power_supply units, or -ENODATA for the sentinel. */
static int book4_scaled(u16 v, union power_supply_propval *val)
{
	if (v == EC_UNKNOWN)
		return -ENODATA;
	val->intval = v * 1000;
	return 0;
}

static int book4_bat_get_property(struct power_supply *psy,
				  enum power_supply_property psp,
				  union power_supply_propval *val)
{
	struct book4_ec *ec = power_supply_get_drvdata(psy);
	int ret;

	guard(mutex)(&ec->lock);
	ret = book4_ec_update(ec);
	if (ret)
		return ret;

	if (psp != POWER_SUPPLY_PROP_PRESENT &&
	    !(ec->flags & EC_FLAG_BAT_PRESENT))
		return -ENODEV;

	switch (psp) {
	case POWER_SUPPLY_PROP_STATUS:
		val->intval = book4_bat_status(ec);
		break;
	case POWER_SUPPLY_PROP_PRESENT:
		val->intval = !!(ec->flags & EC_FLAG_BAT_PRESENT);
		break;
	case POWER_SUPPLY_PROP_TECHNOLOGY:
		val->intval = POWER_SUPPLY_TECHNOLOGY_LION;
		break;
	case POWER_SUPPLY_PROP_CAPACITY:
		if (ec->capacity > 100)		/* 0xffff or a gauge not yet settled */
			return -ENODATA;
		val->intval = ec->capacity;
		break;
	case POWER_SUPPLY_PROP_CHARGE_NOW:
		return book4_scaled(ec->remaining, val);
	case POWER_SUPPLY_PROP_CHARGE_FULL:
		return book4_scaled(ec->full, val);
	case POWER_SUPPLY_PROP_CHARGE_FULL_DESIGN:
		return book4_scaled(ec->design, val);
	case POWER_SUPPLY_PROP_CURRENT_NOW:
		/* The EC reports a magnitude; the direction is in the state byte. */
		ret = book4_scaled(ec->rate, val);
		if (!ret && (ec->state & EC_STATE_DISCHARGING))
			val->intval = -val->intval;
		return ret;
	case POWER_SUPPLY_PROP_VOLTAGE_NOW:
		return book4_scaled(ec->voltage, val);
	case POWER_SUPPLY_PROP_VOLTAGE_MIN_DESIGN:
		return book4_scaled(ec->design_mv, val);
	case POWER_SUPPLY_PROP_MODEL_NAME:
		val->strval = ec->model;
		break;
	case POWER_SUPPLY_PROP_MANUFACTURER:
		val->strval = "Samsung";
		break;
	default:
		return -EINVAL;
	}
	return 0;
}

static const enum power_supply_property book4_ac_props[] = {
	POWER_SUPPLY_PROP_ONLINE,
};

static int book4_ac_get_property(struct power_supply *psy,
				 enum power_supply_property psp,
				 union power_supply_propval *val)
{
	struct book4_ec *ec = power_supply_get_drvdata(psy);
	int ret;

	if (psp != POWER_SUPPLY_PROP_ONLINE)
		return -EINVAL;

	guard(mutex)(&ec->lock);
	ret = book4_ec_update(ec);
	if (ret)
		return ret;
	val->intval = !!(ec->flags & EC_FLAG_AC_ONLINE);
	return 0;
}

static const struct power_supply_desc book4_bat_desc = {
	.name = "book4-battery",
	.type = POWER_SUPPLY_TYPE_BATTERY,
	.properties = book4_bat_props,
	.num_properties = ARRAY_SIZE(book4_bat_props),
	.get_property = book4_bat_get_property,
};

static const struct power_supply_desc book4_ac_desc = {
	.name = "book4-ac",
	.type = POWER_SUPPLY_TYPE_MAINS,
	.properties = book4_ac_props,
	.num_properties = ARRAY_SIZE(book4_ac_props),
	.get_property = book4_ac_get_property,
};

/*
 * No EC interrupt is wired up yet, so poll and announce changes to AC,
 * charge state and capacity; userspace (upower) re-reads on each uevent.
 */
static void book4_ec_poll(struct work_struct *work)
{
	struct book4_ec *ec = container_of(work, struct book4_ec, poll.work);
	u8 flags, state;
	u16 capacity;
	bool changed = false;

	scoped_guard(mutex, &ec->lock) {
		flags = ec->flags;
		state = ec->state;
		capacity = ec->capacity;
		/* Expire the cache; the design values are only read once. */
		ec->updated = jiffies - msecs_to_jiffies(CACHE_MS);
		if (!book4_ec_update(ec))
			changed = flags != ec->flags || state != ec->state ||
				  capacity != ec->capacity;
	}

	if (changed) {
		power_supply_changed(ec->bat);
		power_supply_changed(ec->ac);
	}
	schedule_delayed_work(&ec->poll, msecs_to_jiffies(POLL_MS));
}

static int book4_ec_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct power_supply_config cfg = {};
	struct book4_ec *ec;
	int ret;

	ec = devm_kzalloc(dev, sizeof(*ec), GFP_KERNEL);
	if (!ec)
		return -ENOMEM;
	ec->client = client;

	ret = devm_mutex_init(dev, &ec->lock);
	if (ret)
		return ret;

	/* Talk to the EC once before exposing anything. */
	scoped_guard(mutex, &ec->lock)
		ret = book4_ec_update(ec);
	if (ret)
		return dev_err_probe(dev, ret, "EC not responding\n");

	dev_info(dev, "battery %s: %u%%, %u/%u mAh (design %u), %u mV, AC %s\n",
		 ec->model, ec->capacity, ec->remaining, ec->full, ec->design, ec->voltage,
		 ec->flags & EC_FLAG_AC_ONLINE ? "online" : "offline");

	cfg.drv_data = ec;
	ec->bat = devm_power_supply_register(dev, &book4_bat_desc, &cfg);
	if (IS_ERR(ec->bat))
		return dev_err_probe(dev, PTR_ERR(ec->bat), "registering battery\n");
	ec->ac = devm_power_supply_register(dev, &book4_ac_desc, &cfg);
	if (IS_ERR(ec->ac))
		return dev_err_probe(dev, PTR_ERR(ec->ac), "registering AC adapter\n");

	ret = devm_delayed_work_autocancel(dev, &ec->poll, book4_ec_poll);
	if (ret)
		return ret;
	schedule_delayed_work(&ec->poll, msecs_to_jiffies(POLL_MS));
	return 0;
}

static const struct i2c_device_id book4_ec_id[] = {
	{ "book4-ec" },
	{ }
};
MODULE_DEVICE_TABLE(i2c, book4_ec_id);

static const struct of_device_id book4_ec_of_match[] = {
	{ .compatible = "samsung,galaxy-book4-edge-ec" },
	{ }
};
MODULE_DEVICE_TABLE(of, book4_ec_of_match);

static struct i2c_driver book4_ec_driver = {
	.driver = {
		.name = "book4-ec",
		.of_match_table = book4_ec_of_match,
	},
	.probe = book4_ec_probe,
	.id_table = book4_ec_id,
};
module_i2c_driver(book4_ec_driver);

MODULE_DESCRIPTION("Samsung Galaxy Book4 Edge EC battery and AC driver");
MODULE_LICENSE("GPL");
