# Fedora handoff: test DT 0005/0006 and the emuec orientation fix (10 October)

Written on Arch for a Claude Code session on **Fedora**, booted from the GRUB
entry **"Fedora Linux (7.2.7-book4) - alt DT woofer-names.dtb"** on the 14"
(NP940XMA). Pull first: `cd ~/book4-edge-linux && git pull --ff-only`.

## What is being tested

Built from Arch on 10 October through `install/arch/fedora-shell.sh`:

1. **Device tree** (`tools/kernel/woofer-names-dtb.sh`, branch
   `tmp/woofer-names` in `~/src/patchwork`, patches written to
   `dts/patches/0005-*` and `0006-*` of this system's clone):
   - `0005` names the woofers by side. The shared dtsi calls the SoundWire 0
     woofer `SpkrLeft`, but it is the right one ([audio.md](audio.md)); the 14"
     board file now overrides both prefixes and the two audio-routing sinks.
     Only ALSA control names change.
   - `0006` disables the PTN3222 repeater at I2C 5 / 0x43. It belongs to the
     16"'s USB-A port (Anatase 3f20abc5e); the 14"'s ACPI has nothing there.
     The 0x4f repeater (fingerprint, usb_2) stays.
   Installed as `/boot/dtb-test/woofer-names.dtb` via `/etc/book4/test-dtb`;
   the normal entries are unchanged.
2. **samsung-emuec** with `patches-experimental/0004` and **`0005`**
   (installed in Fedora only by `install/update-emuec-module.sh`, `.prev`
   kept; Arch still has the old module). `0005`: the driver took the plug
   orientation from CC_STATUS 0x11 bits 7:4, which are the attach type
   (charger 1, hub 2, either way round, 9 Oct); it now reads register 0x12
   bits 1:0 (1 = CC1, 2 = CC2; bit 2 set as source). See [TODO.md](TODO.md),
   "External monitor".

## Run

```sh
bash tools/kernel/test-dt-woofers-orientation.sh
```

It checks the running DT first (stops if it is not the new one), then guides
through: ALSA names, `speaker-test` sides, fingerprint present, charger
orientation both ways, and a USB-C hub + monitor capture in both orientations
(`tools/display/usbc-dp-capture.sh`). Log: `~/test-dt-orientation-*.log`,
captures `~/usbc-dp-*.log`.

Pass criteria: new DT running; "Front Left" from the left; `1c7a` present;
orientation `normal` once and `reverse` once with the charger. The monitor
is the open question: a picture in one or both orientations means
orientation was the (main) bug; still AUX timeouts (`AUX -> (ret=-110)`) in
both means a second fault, and the captures show where it stops now.

## After the test

- **DT passes:** make it the default: `echo /dtb-test/woofer-names.dtb |
  sudo tee /etc/book4/default-dtb`, `sudo rm /etc/book4/test-dtb`, rerun the
  hook (`sudo /etc/kernel/install.d/99-book4-devicetree.install add $(cat
  /etc/book4/default-kernel)`), check `cutmem` in grub.cfg. Then flip the UCM
  remap in `userspace/audio/ucm2/Samsung-GalaxyBook4Edge.conf` ("Speakers
  Volume": `SpkrLeft` vindex 0, `SpkrRight` vindex 1, and fix its comments;
  the stock wsa883x order is now right), install with
  `install/update-audio.sh` on Fedora and Arch. Add 0005/0006 to the kernel
  branch `book4/7.2` and `dts/patches/` (commit them from this clone).
- **Orientation passes:** move `0005` from `patches-experimental/` to
  `patches/` (renumber after 0003), then in Arch `fedora-shell.sh
  --sync-modules` to get the module there. Report to Anatase as a new issue
  in `anatase-org/kernel-anatase` (ask the owner before posting).
- **Anything fails:** record it in [TODO.md](TODO.md); rollback the module
  with the `.prev` files (see `install/update-emuec-module.sh`), the DT by
  booting the normal entry.

Record the results in [TODO.md](TODO.md) and push.
