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

**Same result on the Fedora kernel** (`7.2.0-61`, same test, 2 October):
`aosd`, `cxsd` and `ddr` also stay at 0, although that kernel measured about
0.2 W in suspend the day before. These counters are evidently not populated by
this machine's firmware, so they prove nothing either way. Drain has to be
measured from the battery: [`tools/power/drain-test.sh`](../tools/power/drain-test.sh)
records `charge_now` before and after a lid-closed suspend and prints mA and W.

The RTC cannot wake this machine (`/dev/rtc0 not enabled for wakeup events`),
so `rtcwake` is useless here; the test is ended with the power key.

## Leads

- The EC read error during suspend (`EC read failed: -13`) appears on **both**
  kernels (`ene-kb9058-battery` on Fedora, `samsung-galaxybook-ec` on
  Anatase): harmless, not the cause.
- `hwmon hwmon62: PM: parent phy0 should not be sleeping` on resume (ath12k),
  also on both kernels.
- What differs between the good and the bad night: **kernel** (Fedora 7.2.0-61
  vs Anatase 7.2.7-book4) **and desktop** (GNOME vs KDE Plasma, installed
  that evening). KDE's PowerDevil requested the suspend; a desktop that keeps
  waking the machine, or keeps a device busy, would drain it just as well.

## Results

| date | kernel | desktop | lid closed | battery | average |
|---|---|---|---|---|---|
| 1 Oct | Fedora 7.2.0-61 | GNOME | 3 h 04 min | 99 -> 98 % | about 0.2 W |
| 1-2 Oct | Anatase 7.2.7-book4 | KDE Plasma | one night | 100 % -> empty | roughly 3 W or more |
| 2 Oct | Fedora 7.2.0-61 | KDE Plasma | 31 min | 50 -> 50 %, 0 mAh | below the resolution; the overnight rate would have used ~3 % |

The battery values (`charge_now`) update slowly, so short runs are coarse; the
script now waits 60 s after resume before reading. KDE on the Fedora kernel
does not show the overnight drain, which points at the Anatase kernel.

## Next steps

1. ~~Fedora kernel under KDE~~: done, low drain.
2. `drain-test.sh` on the **Anatase kernel under KDE**, 1 hour, to confirm the
   overnight number; then bisect between the two kernels (config, DTB, drivers).

Until then: shut down, or keep the charger connected, when the lid will be
closed for hours.
