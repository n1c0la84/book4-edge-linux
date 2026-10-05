# Anatase drivers (third-party)

**Author:** Antheas Kapenekakis <lkml@antheas.dev>
**Origin:** https://github.com/anatase-org/patchwork, branch `anatase-7.2`
(retrieved 30 September 2026).
**Licence:** GPL-2.0-only (see the SPDX headers).

The two `.c` files here are **unmodified** copies. `Makefile` and `dkms.conf`
are ours, for building them out of tree against a distribution kernel.

Our changes are kept as separate patches in `patches/`, applied at install
time, so the originals stay identifiable and the patches can be sent upstream:

- `0001-samsung-emuec-retry-PD-request-after-hot-plug.patch`
- `0003-samsung-emuec-wake-on-plug-in-into-empty-port.patch` (5 October):
  arms a wake on empty ports while quiesced, so a charger plugged in during
  sleep wakes the machine, is negotiated and charges; attached ports stay
  unarmed (unplug during sleep still safe). Tested on Fedora.
- `0002-samsung-emuec-quiesce-events-across-sleep.patch` (4 October): stops
  the interrupt and sync/HPD work from `PM_SUSPEND_PREPARE` to
  `PM_POST_SUSPEND`, then resyncs. Fixes the machine resetting when a
  charger is unplugged during sleep, and negotiates a charger plugged in
  during sleep on resume (see [docs/power.md](../../docs/power.md)).

`patches-experimental/` is **not** applied by any script:

- `0002-samsung-emuec-resync-after-system-sleep.patch` (3 October): handle a
  charger plugged in during system sleep. Tested once: the plug-in woke the
  machine and the charger was negotiated at 20 V, but the machine then died
  during the next sleep while charging (no crash record). Rolled back; see
  [docs/power.md](../../docs/power.md).
- `0002-v2-samsung-emuec-resync-after-system-sleep.patch`: wakes only on
  empty ports and resyncs on resume. Plug-in and an hour charging in sleep
  passed, but unplugging still reset the machine; the original driver also
  reproduces that reset.
- `0003-samsung-galaxybook-ec-display-off-during-sleep.patch`: experimental
  EC display-state notification; did not prevent the unplug reset.

Further isolation on 3 October found that unbinding only the charging
port's `samsung-emuec` before device suspend or real s2idle avoided the
reset. This implicates driver activity or the USB state established by
its detach path; it does not yet identify a faulty operation. No new driver
fix is applied here. See the [test matrix and scripts](../../docs/power.md#further-isolation-3-october-evening-charging-port-driver-unbind-succeeds).
- 0004 was promoted to `patches/0002` on 4 October.
