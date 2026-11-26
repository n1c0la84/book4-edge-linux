# Drivers (7.2-era archive)

> **Superseded on `linux-book4` 7.3:** On `book4/7.3` (`packages/linux-book4`),
> Anatase's reworked `samsung-galaxybook-ec` and `samsung-emuec` drivers (plus
> our remaining patches) are built directly inside the kernel tree. Everything
> in `drivers/` is kept as 7.2-era DKMS/patch history.

- `anatase/`: Anatase's `ene-kb9058-battery` and `samsung-emuec`, **unmodified**,
  plus our 7.2 patches in `anatase/patches/`, `patches-galaxybook-ec/`, and
  `patches-experimental/`. Built with DKMS as `book4-edge-anatase/1.1` on 7.2.
- `book4-ec/`: our own EC battery driver (same protocol, polling, no IRQ),
  written before we found Anatase. Superseded; kept because it works with the
  fallback DTB (bound by `book4-ec.service` via i2c `new_device`).
- `book4-kbd-backlight/`: keyboard backlight (LED class `samsung::kbd_backlight`)
  via the EC raw target 0x62. Experimental and disabled: it blinks. See
  `docs/keyboard-backlight.md`.
