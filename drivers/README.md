# Drivers

- `anatase/`: Anatase's `ene-kb9058-battery` and `samsung-emuec`, **unmodified**,
  plus our patches in `anatase/patches/`, applied at install time. Built with
  DKMS as `book4-edge-anatase/1.1`. They bind only to nodes in the Anatase DTB.
- `book4-ec/`: our own EC battery driver (same protocol, polling, no IRQ),
  written before we found Anatase. Superseded; kept because it works with the
  fallback DTB (bound by `book4-ec.service` via i2c `new_device`).
- `book4-kbd-backlight/`: keyboard backlight (LED class `samsung::kbd_backlight`)
  via the EC raw target 0x62. Experimental and disabled: it blinks. See
  `docs/keyboard-backlight.md`.
