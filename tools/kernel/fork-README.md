# Linux for the Samsung Galaxy Book4 Edge 14" (Snapdragon X Elite)

This is the kernel that runs on a **Samsung Galaxy Book4 Edge 14"
(NP940XMA, X1E80100)**: the [Anatase](https://github.com/anatase-org/patchwork)
kernel tree with the few patches this machine still needs on top, and a
**sleep kernel** that adds what full s2idle deep sleep needs. Built and tested
on that laptop, under Arch Linux ARM with Omarchy (daily, at EL2 on the
sleep kernel) and Fedora 45.

Everything else (how to install it, the boot setup, firmware, audio,
power notes, what works and what does not) lives in
**[n1c0la84/book4-edge-linux](https://github.com/n1c0la84/book4-edge-linux)**.

## Branches

| branch | base | content |
|---|---|---|
| `book4/7.2` (default) | Anatase `anatase-7.2`, `2ad788424` | 7.2.7 + the patches below: the everyday kernel (`7.2.7-book4`) |
| `book4/7.2-sleep` | `book4/7.2` | + 25 patches for deep sleep: the 7.3 PDC series and DRIPS idle state, the 7.3 LPASS macro runtime-PM and geni fixes, Stephan Gerhold's remoteproc attach (DSPs started by qebspil at EL2), panel supplies not always-on. The daily kernel `7.2.7-book4s`, booted at EL2 |
| `book4/7.2-pdc` | `book4/7.2` | the PDC backport alone, a test (superseded by `book4/7.2-sleep`) |
| `book4/7.2-sleep-own-macros` | `book4/7.2-sleep` | a record: our first VA/WSA macro fixes, replaced by upstream's commits |

The sleep branch's patches, each with its origin, are kept as files in
book4-edge-linux (`tools/kernel/sleep-backport/`), and why each one is there
in its `docs/power.md`. Most of them are in Linux 7.3.

One branch per kernel series, rebased when Anatase moves.

## Patches on top of Anatase

| commit | what | upstream status |
|---|---|---|
| arm64: dts: qcom: hamoa: add CCI0 and CAMSS | camera interface | sent to Anatase ([kernel-anatase#2](https://github.com/anatase-org/kernel-anatase/issues/2)) |
| arm64: dts: qcom: ...-book4-edge-14: enable the front camera | OV02C10 webcam + privacy LED | sent to Anatase (#2) |
| arm64: dts: qcom: ...-book4-edge-14: add tweeters | all four speakers (woofers + tweeters) | sent to Anatase ([#4](https://github.com/anatase-org/kernel-anatase/issues/4)) |
| usb: typec: samsung-emuec: retry the PD request after a hot plug | 20 V charging after replugging | sent to Anatase ([#1](https://github.com/anatase-org/kernel-anatase/issues/1)) |
| usb: typec: samsung-emuec: quiesce event handling across system sleep | no reset when the charger is unplugged during sleep | sent to Anatase ([#3](https://github.com/anatase-org/kernel-anatase/issues/3)) |
| usb: typec: samsung-emuec: wake for a charger plugged in during sleep | charges when plugged in with the lid closed | sent to Anatase (follow-up on #3) |
| usb: typec: samsung-emuec: read the plug orientation from the CC pin | USB-C plug orientation | sent to Anatase |
| arm64: configs: add book4_edge_defconfig | the configuration of the kernel that runs | this branch only |

Every patch also goes to Anatase: this branch should only carry what they
have not taken yet. The patch files themselves are kept in
book4-edge-linux (`dts/patches/`, `drivers/anatase/patches/`), from which
the branch is made (`install/kernel-branch.sh` there).

## Build

    git clone -b book4/7.2 https://github.com/n1c0la84/linux-book4-edge.git
    cd linux-book4-edge
    make LOCALVERSION= book4_edge_defconfig
    make -j$(nproc) LOCALVERSION=

The sleep kernel is built from the patch files by
`tools/kernel/build-sleep-kernel.sh` in book4-edge-linux (release
`7.2.7-book4s`, its own modules and initramfs).

The machine also needs `cutmem` in GRUB, the right device tree and
firmware extracted from Windows: see book4-edge-linux before booting it.

## Credits

The hardware enablement here is overwhelmingly **Anatase's** (Antheas
Kapenekakis: the device tree, the `samsung-galaxybook-ec` and
`samsung-emuec` drivers) and the upstream Linux and Qualcomm developers'.
This branch adds testing on real 14" hardware and a handful of fixes.
Licence: as the kernel (GPL-2.0).

*This file is `.github/README.md`, which GitHub shows instead of the
kernel's own [README](../README).*
