# Power: suspend drain

## Symptom (2 October 2026, Anatase kernel `7.2.7-book4`, KDE Plasma)

Lid closed at 18:42 on 1 October with the battery full and the charger
unplugged; the next morning the battery was empty. The log shows a normal
suspend (`PM: suspend entry (s2idle)`) and nothing after it, so the machine
slept and drained at roughly 3 W or more. On the stock Fedora kernel the same
machine had measured about 0.2 W (1 % in 3 h, 1 October, GNOME).

## Measurement

[`tools/power/suspend-test.sh`](../tools/power/suspend-test.sh) reads the SoC
sleep counters in `/sys/kernel/debug/qcom_stats/` before and after one
suspend:

| counter | meaning | Anatase kernel, 2.5 min suspend |
|---|---|---|
| `aosd` | AOSS (always-on subsystem) sleep, whole SoC | 0 -> 0 |
| `cxsd` | CX rail collapse | 0 -> 0 |
| `ddr` | DDR self-refresh / low-power modes | 0 -> 0 |
| `adsp`, `cdsp` | DSP sleep time | increased (the DSPs do sleep) |

So the application processors and DSPs go idle but the SoC as a whole never
power-collapses: something keeps a vote on CX or the always-on subsystem.

The RTC cannot wake this machine (`/dev/rtc0 not enabled for wakeup events`),
so `rtcwake` is useless here; the test is ended with the power key.

## Leads

- During suspend `samsung-galaxybook-ec 4-0064: EC event read failed: -13` and
  `EC read failed: -13`: the EC driver tries to talk over I2C after the
  controller has been suspended. Anatase's EC driver is new in this kernel (the
  Fedora kernel runs `ene-kb9058-battery` via DKMS instead), so it is the first
  suspect.
- `hwmon hwmon62: PM: parent phy0 should not be sleeping` on resume (ath12k).

## Next steps

1. Same test on the Fedora kernel ("(other)" in the GRUB menu). If the
   counters rise there, the difference is in the Anatase kernel, config or
   DTB; if they stay at 0 there too, the counters are not meaningful on this
   firmware and drain has to be measured from the battery instead.
2. On the Anatase kernel, unbind `samsung-galaxybook-ec` (then other drivers in
   turn) before suspending, and watch the counters.

Until then: shut down, or keep the charger connected, when the lid will be
closed for hours.
