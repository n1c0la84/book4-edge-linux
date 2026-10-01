// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2026 Antheas Kapenekakis <lkml@antheas.dev>
 *
 * Report battery and AC adapter status through the ENE KB9058 EC mailbox.
 * The NP750XQB ACPI ECTC, BATC and ADP1 methods describe the battery
 * register layout used here.
 */

#include <linux/bitops.h>
#include <linux/cleanup.h>
#include <linux/delay.h>
#include <linux/errno.h>
#include <linux/i2c.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/power_supply.h>
#include <linux/slab.h>
#include <linux/string.h>

#define KB9058_FLAGS		0x80
#define KB9058_BAT_STATUS	0x84
#define KB9058_REMAINING	0xa0
#define KB9058_BAT_VOLTAGE	0xa4
#define KB9058_CAPACITY	0xb0
#define KB9058_DESIGN_VOLTAGE	0xb4
#define KB9058_CYCLES		0xd0

#define KB9058_BAT_PRESENT	BIT(0)
#define KB9058_AC_PRESENT	BIT(2)
#define KB9058_BAT_DISCHARGING	BIT(0)
#define KB9058_BAT_CHARGING	BIT(1)
#define KB9058_BAT_FULL		BIT(3)

struct kb9058_battery_data {
	int status;
	int present;
	int ac_online;
	int charge_now;
	int charge_full;
	int charge_full_design;
	int voltage_now;
	int voltage_min_design;
	int current_now;
	int cycle_count;
};

struct kb9058_battery {
	struct i2c_client *client;
	struct power_supply *battery;
	struct power_supply *ac;
	/* Serializes mailbox transactions and cached power-supply properties. */
	struct mutex lock;
	struct kb9058_battery_data data;
};

static int kb9058_battery_read_byte(struct i2c_client *client, u8 reg, u8 *value)
{
	u8 select[] = { 0x40, 0x00, 0xf4, 0x80, reg };
	u8 execute[] = { 0x40, 0x00, 0xff, 0x10, 0x88 };
	u8 request[] = { 0x30, 0x00, 0xf4, 0x80 };
	u8 response[2];
	struct i2c_msg msg[] = {
		{ .addr = client->addr, .len = sizeof(request), .buf = request },
		{ .addr = client->addr, .flags = I2C_M_RD,
		  .len = sizeof(response), .buf = response },
	};
	int ret;

	ret = i2c_master_send(client, select, sizeof(select));
	if (ret != sizeof(select))
		return ret < 0 ? ret : -EIO;

	usleep_range(5000, 6000);

	ret = i2c_master_send(client, execute, sizeof(execute));
	if (ret != sizeof(execute))
		return ret < 0 ? ret : -EIO;

	usleep_range(5000, 6000);

	ret = i2c_transfer(client->adapter, msg, ARRAY_SIZE(msg));
	if (ret != ARRAY_SIZE(msg))
		return ret < 0 ? ret : -EIO;
	if (response[0] != 0x50)
		return -EIO;

	*value = response[1];
	return 0;
}

static int kb9058_battery_read_word(struct i2c_client *client, u8 reg,
					unsigned int offset, int *value)
{
	u8 low, high;
	int ret;

	ret = kb9058_battery_read_byte(client, reg + offset, &high);
	if (ret)
		return ret;
	ret = kb9058_battery_read_byte(client, reg + offset + 1, &low);
	if (ret)
		return ret;

	*value = (high << 8) | low;
	return 0;
}

static int kb9058_battery_refresh(struct kb9058_battery *ec,
				      struct kb9058_battery_data *data)
{
	struct i2c_client *client = ec->client;
	u8 flags, state;
	int current_ma;
	int ret;

	ret = kb9058_battery_read_byte(client, KB9058_FLAGS, &flags);
	if (ret)
		return ret;
	ret = kb9058_battery_read_byte(client, KB9058_BAT_STATUS, &state);
	if (ret)
		return ret;

	data->present = !!(flags & KB9058_BAT_PRESENT);
	data->ac_online = !!(flags & KB9058_AC_PRESENT);

	if (state & KB9058_BAT_FULL)
		data->status = POWER_SUPPLY_STATUS_FULL;
	else if (state & KB9058_BAT_CHARGING)
		data->status = POWER_SUPPLY_STATUS_CHARGING;
	else if (state & KB9058_BAT_DISCHARGING)
		data->status = POWER_SUPPLY_STATUS_DISCHARGING;
	else
		data->status = POWER_SUPPLY_STATUS_NOT_CHARGING;

	/* BATC._BST reads the upper big-endian word of B1RR. */
	ret = kb9058_battery_read_word(client, KB9058_REMAINING, 2,
					   &data->charge_now);
	if (ret)
		return ret;
	ret = kb9058_battery_read_word(client, KB9058_BAT_VOLTAGE, 2,
					   &data->voltage_now);
	if (ret)
		return ret;
	ret = kb9058_battery_read_word(client, KB9058_BAT_VOLTAGE, 0,
					   &current_ma);
	if (ret)
		return ret;
	/* BATC._BIX reads design capacity from the lower word of B1AF. */
	ret = kb9058_battery_read_word(client, KB9058_CAPACITY, 0,
					   &data->charge_full_design);
	if (ret)
		return ret;
	ret = kb9058_battery_read_word(client, KB9058_CAPACITY, 2,
					   &data->charge_full);
	if (ret)
		return ret;
	ret = kb9058_battery_read_word(client, KB9058_DESIGN_VOLTAGE, 0,
					   &data->voltage_min_design);
	if (ret)
		return ret;
	ret = kb9058_battery_read_word(client, KB9058_CYCLES, 0,
					   &data->cycle_count);
	if (ret)
		return ret;

	/* Unknown EC values match BATC._BST/_BIX's 0xffff sentinel. */
	if (data->charge_now == 0xffff)
		data->charge_now = -1;
	if (data->charge_full_design == 0xffff)
		data->charge_full_design = -1;
	if (data->charge_full == 0xffff)
		data->charge_full = -1;
	if (data->voltage_now == 0xffff)
		data->voltage_now = -1;
	if (data->voltage_min_design == 0xffff)
		data->voltage_min_design = -1;
	if (current_ma == 0xffff)
		current_ma = -1;
	if (data->cycle_count == 0xffff)
		data->cycle_count = -1;

	if (current_ma >= 0) {
		current_ma = abs((s16)current_ma);
		if (data->status == POWER_SUPPLY_STATUS_DISCHARGING)
			current_ma = -current_ma;
	}

	data->current_now = current_ma;

	/* EC units are mAh, mV and mA; power_supply uses micro units. */
	if (data->charge_now >= 0)
		data->charge_now *= 1000;
	if (data->charge_full >= 0)
		data->charge_full *= 1000;
	if (data->charge_full_design >= 0)
		data->charge_full_design *= 1000;
	if (data->voltage_now >= 0)
		data->voltage_now *= 1000;
	if (data->voltage_min_design >= 0)
		data->voltage_min_design *= 1000;
	if (current_ma != -1)
		data->current_now *= 1000;

	return 0;
}

static enum power_supply_property kb9058_battery_properties[] = {
	POWER_SUPPLY_PROP_STATUS,
	POWER_SUPPLY_PROP_PRESENT,
	POWER_SUPPLY_PROP_TECHNOLOGY,
	POWER_SUPPLY_PROP_CAPACITY,
	POWER_SUPPLY_PROP_CHARGE_NOW,
	POWER_SUPPLY_PROP_CHARGE_FULL,
	POWER_SUPPLY_PROP_CHARGE_FULL_DESIGN,
	POWER_SUPPLY_PROP_VOLTAGE_NOW,
	POWER_SUPPLY_PROP_VOLTAGE_MIN_DESIGN,
	POWER_SUPPLY_PROP_CURRENT_NOW,
	POWER_SUPPLY_PROP_CYCLE_COUNT,
};

static int kb9058_battery_get_property(struct power_supply *psy,
					   enum power_supply_property prop,
					   union power_supply_propval *val)
{
	struct kb9058_battery *ec = power_supply_get_drvdata(psy);
	const struct kb9058_battery_data *data = &ec->data;
	int value;

	guard(mutex)(&ec->lock);

	switch (prop) {
	case POWER_SUPPLY_PROP_STATUS:
		value = data->status;
		break;
	case POWER_SUPPLY_PROP_PRESENT:
		value = data->present;
		break;
	case POWER_SUPPLY_PROP_TECHNOLOGY:
		value = POWER_SUPPLY_TECHNOLOGY_LION;
		break;
	case POWER_SUPPLY_PROP_CAPACITY:
		if (data->charge_now < 0 || data->charge_full <= 0)
			return -ENODATA;
		value = clamp(100 * (data->charge_now / 1000) /
			      (data->charge_full / 1000), 0, 100);
		break;
	case POWER_SUPPLY_PROP_CHARGE_NOW:
		value = data->charge_now;
		break;
	case POWER_SUPPLY_PROP_CHARGE_FULL:
		value = data->charge_full;
		break;
	case POWER_SUPPLY_PROP_CHARGE_FULL_DESIGN:
		value = data->charge_full_design;
		break;
	case POWER_SUPPLY_PROP_VOLTAGE_NOW:
		value = data->voltage_now;
		break;
	case POWER_SUPPLY_PROP_VOLTAGE_MIN_DESIGN:
		value = data->voltage_min_design;
		break;
	case POWER_SUPPLY_PROP_CURRENT_NOW:
		value = data->current_now;
		break;
	case POWER_SUPPLY_PROP_CYCLE_COUNT:
		value = data->cycle_count;
		break;
	default:
		return -EINVAL;
	}

	/* Negative current is valid while discharging; -1 marks unknown data. */
	if (value < 0 && (prop != POWER_SUPPLY_PROP_CURRENT_NOW || value == -1))
		return -ENODATA;

	val->intval = value;
	return 0;
}

static int kb9058_ac_get_property(struct power_supply *psy,
				      enum power_supply_property prop,
				      union power_supply_propval *val)
{
	struct kb9058_battery *ec = power_supply_get_drvdata(psy);

	if (prop != POWER_SUPPLY_PROP_ONLINE)
		return -EINVAL;

	guard(mutex)(&ec->lock);
	val->intval = ec->data.ac_online;
	return 0;
}

static enum power_supply_property kb9058_ac_properties[] = {
	POWER_SUPPLY_PROP_ONLINE,
};

static const struct power_supply_desc kb9058_battery_desc = {
	.name = "kb9058-battery",
	.type = POWER_SUPPLY_TYPE_BATTERY,
	.properties = kb9058_battery_properties,
	.num_properties = ARRAY_SIZE(kb9058_battery_properties),
	.get_property = kb9058_battery_get_property,
};

static const struct power_supply_desc kb9058_ac_desc = {
	.name = "kb9058-ac",
	.type = POWER_SUPPLY_TYPE_MAINS,
	.properties = kb9058_ac_properties,
	.num_properties = ARRAY_SIZE(kb9058_ac_properties),
	.get_property = kb9058_ac_get_property,
};

static irqreturn_t kb9058_battery_irq_thread(int irq, void *ptr)
{
	struct kb9058_battery *ec = ptr;
	struct kb9058_battery_data data = {};
	bool changed = false;
	int ret;

	scoped_guard(mutex, &ec->lock) {
		ret = kb9058_battery_refresh(ec, &data);
		if (ret) {
			dev_warn_ratelimited(&ec->client->dev,
					     "EC read failed: %d\n", ret);
		} else {
			changed = memcmp(&ec->data, &data, sizeof(data));
			ec->data = data;
		}
	}

	if (!ret && changed) {
		power_supply_changed(ec->battery);
		power_supply_changed(ec->ac);
	}

	return IRQ_HANDLED;
}

static int kb9058_battery_probe(struct i2c_client *client)
{
	struct power_supply_config cfg = {};
	struct kb9058_battery *ec;
	int ret;

	if (!i2c_check_functionality(client->adapter, I2C_FUNC_I2C))
		return dev_err_probe(&client->dev, -EOPNOTSUPP,
				     "adapter lacks combined I2C transfers\n");
	if (!client->irq)
		return dev_err_probe(&client->dev, -EINVAL,
				     "EC interrupt is required\n");

	ec = devm_kzalloc(&client->dev, sizeof(*ec), GFP_KERNEL);
	if (!ec)
		return -ENOMEM;

	ec->client = client;
	mutex_init(&ec->lock);

	ret = kb9058_battery_refresh(ec, &ec->data);
	if (ret)
		return dev_err_probe(&client->dev, ret, "failed to read EC battery\n");

	cfg.drv_data = ec;
	cfg.fwnode = dev_fwnode(&client->dev);
	ec->battery = devm_power_supply_register(&client->dev,
						  &kb9058_battery_desc, &cfg);
	if (IS_ERR(ec->battery))
		return dev_err_probe(&client->dev, PTR_ERR(ec->battery),
				     "failed to register battery\n");

	ec->ac = devm_power_supply_register(&client->dev, &kb9058_ac_desc,
					     &cfg);
	if (IS_ERR(ec->ac))
		return dev_err_probe(&client->dev, PTR_ERR(ec->ac),
				     "failed to register AC supply\n");

	i2c_set_clientdata(client, ec);
	return devm_request_threaded_irq(&client->dev, client->irq, NULL,
					 kb9058_battery_irq_thread, IRQF_ONESHOT,
					 dev_name(&client->dev), ec);
}

static const struct of_device_id kb9058_battery_of_match[] = {
	{ .compatible = "ene,kb9058-battery" },
	{}
};
MODULE_DEVICE_TABLE(of, kb9058_battery_of_match);

static struct i2c_driver kb9058_battery_driver = {
	.driver = {
		.name = "ene-kb9058-battery",
		.of_match_table = kb9058_battery_of_match,
	},
	.probe = kb9058_battery_probe,
};
module_i2c_driver(kb9058_battery_driver);

MODULE_DESCRIPTION("ENE KB9058 EC battery and AC adapter");
MODULE_LICENSE("GPL");
