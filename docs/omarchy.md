# Carrying this to Arch / Omarchy Dragon

This repository is Fedora-only. The hardware knowledge in it is not, and the
clearest unoccupied space for this machine right now is
**[Omarchy Dragon](https://omarchy.org/news/2026/09/introducing-omarchy-dragon/)**,
the Snapdragon effort for Omarchy (Arch-based): as far as we could tell from
its public issue threads (1 October 2026), nobody there is working on a Samsung.

## What exists there

- **Official**: `omacom/omarchy#8672` (generic Snapdragon X support on aarch64)
  and `omacom/omarchy-iso#129` (boot and install on Snapdragon X ARM64), both
  by Birk Skyum.
- **Community port**: `bprendie/omarchy-snapdragon` — a real Omarchy 4.0.3 for
  Snapdragon X Elite with downloadable ISOs, a Quattro installer and a
  kernel-update pipeline.
- **Machines covered**: ThinkPad T14s Gen 6, HP, ASUS A16/A14, Yoga Slim 7x,
  Surface Laptop 8. No Samsung.

**The architectural surprise**: the community port is Arch userspace on an
**Ubuntu kernel** (`7.2.0-18-qcom-x1e`). So "port this to Arch" is really "which
kernel carries the Samsung drivers", and today only Anatase's does. Neither
Ubuntu nor Arch has `samsung-galaxybook-ec` or `samsung-emuec`.

## What is already portable here, and what is not

Distribution-neutral — moves as-is:

    dts/                     device tree (though prefer building it from
                             Anatase's tree, see kernel.md)
    firmware/                what to extract from Windows, and the paths
    userspace/audio/         UCM profiles and PipeWire configuration
    userspace/keyboard/      udev rule
    userspace/modprobe/      blacklists
    userspace/bluetooth/     the address-from-Windows service
    tools/                   EC tooling
    docs/                    all of it

Fedora-specific — needs an Arch counterpart:

    userspace/boot/          kernel-install hook (Arch: mkinitcpio + a
                             systemd-boot entry, or a pacman hook)
    userspace/dracut/        initramfs firmware inclusion (Arch: mkinitcpio
                             FILES=/MODULES=)
    userspace/dnf/           update guards (Arch: pacman hooks)
    install/install-fedora.sh

ciscobugger's 15.6" repository is already Arch-shaped — it carries
`boot/mkinitcpio-book4.conf` and a systemd-boot loader entry — so it is a
working reference for the pieces this repository does not have.

## The two routes

**Short route — make it work.** DKMS the two drivers onto whatever kernel
Omarchy ships, plus the DTB, firmware and UCM profile. The drivers build out of
tree against standard headers, so this is mechanical. It leaves every Omarchy
user on a DKMS package that must follow Anatase's tree as it moves — and it has
moved substantially in a single day.

**Long route — make it unnecessary.** Neither driver is in mainline; both live
only in Anatase's fork. Until that changes, *every* distribution needs a patched
kernel for this laptop. Helping get them upstream — even only as a tester
offering `Tested-by:` on real 14" hardware — would give Omarchy, Ubuntu, Arch
and Fedora this machine for free, and is worth more than any single port.

## What we can actually offer that project

A working 14" X1E80100, documented. The machines mentioned in their public
threads (as of 1 October 2026) are Surface, Lenovo Yoga and similar laptops;
we found no Samsung among them, so test cycles on one may be useful.

An issue on `omacom/omarchy` saying "I have a Galaxy Book4 Edge 14" running
mainline-based Linux, here is the state, here is what I can test" costs ten
minutes, and may well be the most useful thing this repository can offer them.

Be honest in it about what is ours and what is not: the hardware enablement is
overwhelmingly Anatase's and the upstream DTS authors', and
[CREDITS.md](../CREDITS.md) says so. What we bring is a machine, test cycles,
and an integration layer that has been shaken out on a real system.
