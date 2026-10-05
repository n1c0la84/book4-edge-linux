# Audio

With the Anatase device tree the sound card is named
`X1E80100-GalaxyBook4Edge`, and the speakers are two WSA883x amplifiers
(`SpkrLeft`, `SpkrRight`), one on each WSA macro, plus a WCD938x headset codec
and two DMICs.

Two things are missing from stock Fedora:

1. **Topology.** The kernel loads `qcom/x1e80100/<card name>-tplg.bin`, and no
   `X1E80100-GalaxyBook4Edge-tplg.bin` is shipped, so the card fails with
   `-ENOENT`. The card's DAI links (WCD playback/capture, WSA playback, VA
   capture, same back-end ids) match the CRD's exactly, so we alias it:

       /usr/lib/firmware/updates/qcom/x1e80100/X1E80100-GalaxyBook4Edge-tplg.bin.xz
           -> ../../../qcom/x1e80100/X1E80100-CRD-tplg.bin.xz

2. **UCM profile.** UCM looks up `conf.d/x1e80100/<card long name>.conf`, where
   the long name is built from DMI (here
   `SAMSUNGELECTRONICSCO.LTD.-GalaxyBook4Edge-2.1-NP940XMA_KB1IT`). Our profile,
   [`userspace/audio/ucm2`](../userspace/audio/ucm2), is the X1E80100 CRD
   profile with the WSA883x two-speaker sequences and the WSA883x `Speakers`
   volume remap.

The speaker PCM is **four-channel** (the CRD topology drives four speakers):
channel 1 is the left speaker, channel 2 the right, 3 and 4 are silent. Stereo
content plays correctly. Declaring it as two channels makes PipeWire drop the
whole profile (`snd_pcm_hw_params_set_channels(2) failed`).

Internal microphones: two DMICs on DMIC0/DMIC1 (DMIC2/3 are silent; the
`dmic23` pin group is configured but nothing answers there). The stock
sequences set `VA_DEC0/1 Volume` to 100 (+16 dB), which leaves speech around
-34 dBFS. At 120 (+36 dB) normal speech reached about -14 dBFS but louder
speech clipped (407 samples in 5 s) and sounded distorted, so the profile uses
114 (+30 dB): normal speech around -20 dBFS with headroom. The enable sequences are inlined because an
`EnableSequence` placed after an `Include` of the stock one does not override
it.

Each speaker bus also enumerates a second WSA883x (part `0x0202`) at
SoundWire address 1 that no device tree describes (checked 5 October:
`sdw:1:0:0217:0202:00:1` and `sdw:4:0:0217:0202:00:1`, no driver bound).
Samsung lists **2 × 4 W woofers + 2 × 2.7 W tweeters**, behind one long slit
at each end of the base.

## Four speakers (5 October)

The address-1 amplifiers are the **tweeters**, and Linux used to drive only
the **woofers** (a tone ladder: woofers heard from 300 Hz, tweeters from
600 Hz). The device tree
[`-14-speakers.dts`](../dts/src/x1e80100-samsung-galaxy-book4-edge-14-speakers.dts)
adds them as `SpkrLeft2`/`SpkrRight2` on SoundWire ports `<4 5 6 7>`, fed by
the WSA macros' second output (RX1), exactly as on the CRD. It works; no driver
changes are needed. Install it with `install/speakers-dtb.sh` (test entry).

| PCM channel | Macro path | Amplifier | Speaker |
|---|---|---|---|
| 1 (FL) | WSA2 RX0 | `SpkrRight` (bus 4, addr 2) | left woofer |
| 2 (FR) | WSA RX0 | `SpkrLeft` (bus 1, addr 2) | right woofer |
| 3 (RL) | WSA2 RX1 | `SpkrRight2` (bus 4, addr 1) | left tweeter |
| 4 (RR) | WSA RX1 | `SpkrLeft2` (bus 1, addr 1) | right tweeter |

The DT names are left/right swapped (inherited); the UCM volume remap uses the
physical order.

Software: the UCM profile switches the tweeters with the woofers when their
controls exist (same profile for both DTBs), and `Speakers Volume` covers all
four PAs. A PipeWire filter-chain,
[`pipewire/book4-speakers.conf`](../userspace/audio/pipewire/book4-speakers.conf),
is a WirePlumber *smart filter* on the Speaker sink: woofers get full-range
stereo, tweeters a 2 kHz 4th-order Linkwitz-Riley high-pass. A WirePlumber
rule disables up-mixing on the raw 4-channel sink so nothing full-range
reaches the tweeters by accident. `install/update-audio.sh` installs all of it.
Windows does the same fan-out (`MapSpkrStereoChToQuadDevices=1`, a
4-channel `SpeakerInternalChannelMapping`), with its own (unknown) tuning.

Pitfalls met on the way: a quiet 1 kHz test tone is near the bottom of the
tweeters' range and disappears in the amplifiers' hiss when the woofers are
muted, which first looked like "the tweeters' ports carry no audio" (test
with 3 kHz or more). The variant with shared ports
([`-14-speakers-shared.dts`](../dts/src/x1e80100-samsung-galaxy-book4-edge-14-speakers-shared.dts),
both amps on `<1 2 3 7>`) also plays, but sends the woofer's full-range
signal to the tweeter: test only. A filter-chain output port cannot be both
linked inside the graph and a graph output (`use copy`).

Test scripts: [`tools/audio`](../tools/audio) (`speakers-voices.sh`,
`speakers-check.sh`; the rest are the investigation's raw tests).

Testing a profile without installing it:

    systemctl --user set-environment ALSA_CONFIG_UCM2=/path/to/ucm2-copy
    systemctl --user restart wireplumber pipewire pipewire-pulse
    # WIREPLUMBER_DEBUG=spa.alsa:4 shows why a profile is rejected
