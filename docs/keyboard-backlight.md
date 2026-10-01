# Keyboard backlight (experimental, disabled)

Status: we can switch the backlight on and set its level from Linux, but no
version of our driver keeps it on reliably. The driver
([drivers/book4-kbd-backlight](../drivers/book4-kbd-backlight)) is installed
via DKMS but **disabled** (`install/disable-kbd-backlight.sh`): its current
version makes the light blink.

## What is known

From the Windows `EC2.sys` driver (see [ec-protocol.md](ec-protocol.md)):

- `IOCTL_SET_KBDBLT` takes two bytes, logged as `timeout` and `Level`, and
  queues the command `{0x10, timeout, level}`. `IOCTL_GET_KBDBLT` queues
  `{0x11}`. There are also `IOCTL_SET_KBDBLT_TEST`, `START/STOP_KBDBLT_TEST`
  and `InvalidateKeybklCmdBeforeTest`.
- Queued commands are sent as a plain I2C write on the EC's "raw" target:
  **0x62 on the b94000 bus** (ACPI `\_SB.I2C6`), which the Anatase device tree
  enables. 0x62 answers a plain 12-byte read (the EC event queue).

Measured on the 14" (NP940XMA), sending the command by hand
([tools/ec/kbd-backlight.py](../tools/ec/kbd-backlight.py)):

| Observation | Result |
|---|---|
| level | 0 = off, 1/2/3 = increasing brightness, 4 and above act as 3 |
| one command, any "timeout" | the light goes off **about 3 s** after the command (timed with 10 and 11; 0, 5 and 255 behaved alike) |
| same command again 7 s later | lights again, off ~3 s after it ([tools/ec/kbd-timer-test.sh](../tools/ec/kbd-timer-test.sh)) |
| key presses | do **not** relight it; the EC does not do this by itself |

## Driver attempts

All three register `samsung::kbd_backlight` (LED class, max 3); UPower and
GNOME pick it up (quick-settings slider works), and the level is set correctly.
The problem is purely the timing towards the EC.

| Version | Strategy | Second byte | Result |
|---|---|---|---|
| 1.0 | resend on key press, at most once per second | 30 | on while typing continuously; off during any pause > ~3 s, back on the next key |
| 1.1 | on key press light it, then refresh every 2 s until 30 s idle | 255 | blinks |
| 1.2 | same as 1.1 | 30 | blinks |

So the second byte is not the cause: sending the command while the light is
already on, every 2 s, makes it blink, while resending on key presses (1.0)
did not visibly. Windows evidently does something else.

## Ideas for next time

- Read back state: send `{0x11}` (GET) and look for the answer in the event
  queue at 0x62 (plain 12-byte read); refresh only when the EC reports the
  light off.
- Find how EC2.sys decides when to send `{0x10, ...}`: which events trigger it
  (hotkey events with `byte0 == 1` are handled in the same work item), and what
  `InvalidateKeybklCmdBeforeTest` removes from the queue.
- Try refresh intervals around 2.5-3 s, or only resending when no command was
  sent in the last ~2.5 s.
