# Fedora handoff: next session (written 5 October on Arch)

Two items, in this order. Pull first: `cd ~/book4-edge-linux && git pull --ff-only`.

## 1. CPU frequency scaling (5 minutes)

Without `scmi-cpufreq` the X1E cores sit at the firmware's 1.19 GHz step
under any load; the module has no autoload alias, so nothing loads it. Fixed
on Arch on 5 October (×2.9 single-thread, ×2.5 on 12 threads, same idle
power; details in [power.md](power.md#cpu-frequency-scaling-was-off-5-october-2026)).
Fedora runs the same kernel and modules, so it is almost certainly slow too.

```sh
ls /sys/devices/system/cpu/cpufreq/            # expected now: nothing
openssl speed -seconds 3 sha256 | tail -1      # last column ~850000k without it
sudo install -D -m 644 userspace/modules-load/book4-cpufreq.conf /etc/modules-load.d/book4-cpufreq.conf
sudo modprobe scmi-cpufreq
ls /sys/devices/system/cpu/cpufreq/            # policy0 policy4 policy8
openssl speed -seconds 3 sha256 | tail -1      # ~2400000k
```

Also check the fallback "(other)" kernel once (does it ship `scmi-cpufreq`?
a missing module only logs a failure at boot). Then tick the TODO item and
note Fedora's numbers in power.md.

## 2. Four speakers instead of two

**What we know (Arch, 5 October).** Each speaker SoundWire bus has **two**
WSA883x amplifiers that answer on the bus, but the device tree describes only
one of them, so Linux drives two speakers out of four. That would explain
audio that is quiet and thin even at 100 %.

| bus (DT node) | address 2 | address 1 |
|---|---|---|
| `soundwire@6b10000` (WSA macro) | `speaker@0,2`, `SpkrLeft`, driven | `sdw:1:0:0217:0202:00:1`, **no driver** |
| `soundwire@6ab0000` (WSA2 macro) | `speaker@0,2`, `SpkrRight`, driven | `sdw:4:0:0217:0202:00:1`, **no driver** |

Both are part `0x0202` (WSA883x, same as the described ones). The described
nodes: `compatible = "sdw10217020200"`, `reg = <0 2>`, `reset-gpios` on LPASS
TLMM 12 (active low, so it is shared and already high: the extra amps
enumerate), shared `vdd-supply`, `qcom,port-mapping = <1 2 3 7>`. The sound
card routes `SpkrLeft IN <- WSA WSA_SPK1 OUT` and `SpkrRight IN <- WSA2
WSA_SPK2 OUT`, so each macro has one speaker output unused. The CRD audio
topology we alias already sends **4 channels** to the speakers; our UCM
profile uses 1 (left) and 2 (right) and leaves 3-4 silent.

**Plan.**

1. In the Anatase tree, compare `x1e80100-samsung-galaxy-book4-edge-14.dts`
   with boards that describe four speakers: `x1e80100-crd.dts`,
   `x1e80100-lenovo-yoga-slim7x.dts` (woofer + tweeter per side), and
   `sc8280xp-lenovo-thinkpad-x13s.dts` (two WSA883x on one bus:
   `reg = <0 1>` and `<0 2>`, port mappings `<1 2 3 7>` and `<4 5 6 8>`).
   Check the current Anatase DTS first; it may have changed.
2. Add `speaker@0,1` to each bus (same compatible, reset GPIO and supply,
   distinct `sound-name-prefix`, e.g. `SpkrLeft2`/`SpkrRight2` until we know
   which is woofer and which tweeter, and the second port mapping), and the
   routing for the free outputs (`WSA WSA_SPK2 OUT`, `WSA2 WSA_SPK1 OUT`).
   Build it as an experimental DTB the way the camera DTB was done
   ([camera.md](camera.md), `dts/patches/`), on top of the camera DTB that is
   the default now, and boot it from a test entry (`/etc/book4/test-dtb`)
   so the normal entry stays as it is.
3. Check that both new amps bind (`wsa883x-codec`), then extend the UCM
   profile to 4 channels: enable sequences for the new amps, channels 3-4
   mapped to them, start from the CRD / Yoga UCM files in alsa-ucm-conf.
4. Find out which pair is which: play each channel alone at **low volume**
   (`speaker-test -c 4 -s N`), by ear and by putting a hand on the grilles.

**Caution: tweeters.** Windows probably splits bass from treble in its audio
DSP; Linux has no crossover here, so a tweeter would get the full-range
signal. Keep the volume low while testing, keep the new amps' `PA` gain at
its lowest steps at first, and do not play bass-heavy material loud through
a pair that turns out to be tweeters. If they are tweeters, a crossover in
PipeWire (filter-chain) is the follow-up, as other X1E laptops do it.

Rollback: delete `/etc/book4/test-dtb` and rerun the boot hook; UCM changes
live in `userspace/audio/` and are only installed by hand.

## 3. Our kernel branch, public (written 6 October on Arch)

> **Done 6 October** from Arch through the Fedora container:
> https://github.com/n1c0la84/linux-book4-edge/tree/book4/7.2, checked
> against what runs (see [kernel.md](kernel.md)). The tweeter patch had to be
> rebased onto the camera patch first (`tools/kernel/merge-dts-patches.sh`).
> Remaining: the Arch `linux-book4` PKGBUILD.

Decision (6 October): the samsung EC and USB-C drivers exist only in
Anatase's tree and may not reach mainline soon, so this machine needs a
custom kernel for the foreseeable future. Not an independent kernel, but a
**lightweight public fork**: Anatase's tree plus our few patches as commits,
one branch per series (`book4/7.2`), rebased when Anatase moves; every patch
also offered to Anatase, so the branch only carries what they have not taken.
Our repo stays the integration layer (patch files, config, build scripts).

[`install/kernel-branch.sh`](../install/kernel-branch.sh), in Fedora (or
`install/arch/fedora-shell.sh` from Arch):

```sh
cd ~/book4-edge-linux && git pull --ff-only
git -C ~/src/patchwork status --short --branch     # must be clean (tracked files)
bash install/kernel-branch.sh                       # local branch book4/7.2 only
bash install/kernel-branch.sh --push                # then: fork (asks YES) and push
```

It creates `book4/7.2` from the base the running kernel was built on
(`2ad788424`), applies `dts/patches/` with `git am` and
`drivers/anatase/patches/` as commits, adds the running config as
`arch/arm64/configs/book4_edge_defconfig`, and shows the difference to the
branch the installed kernel came from (expected: none, or only patches newer
than that build). `--push` forks `anatase-org/patchwork` as
`<you>/linux-book4-edge` (once), pushes the branch and makes it the default.
Then: an Arch `PKGBUILD` (`linux-book4`) building from that branch, so Arch
gets a real kernel package instead of copied modules.
