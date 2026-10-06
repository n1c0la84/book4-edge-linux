# Linux for the Samsung Galaxy Book4 Edge 14" (Snapdragon X Elite)

This is the kernel that runs on a **Samsung Galaxy Book4 Edge 14"
(NP940XMA, X1E80100)**: the [Anatase](https://github.com/anatase-org/patchwork)
kernel tree with the few patches this machine still needs on top. It is
built and tested on that laptop, under Fedora 45 and Arch Linux ARM with
Omarchy.

Everything else (how to install it, the boot setup, firmware, audio,
power notes, what works and what does not) lives in
**[n1c0la84/book4-edge-linux](https://github.com/n1c0la84/book4-edge-linux)**.

## Branches

| branch | base | content |
|---|---|---|
| `book4/7.2` (default) | Anatase `anatase-7.2`, `2ad788424` | 7.2.7 + the patches below |

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
