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

## Four speakers: what is known (5 October)

Test DTBs (not default): [`-14-speakers.dts`](../dts/src/x1e80100-samsung-galaxy-book4-edge-14-speakers.dts)
adds the address-1 amplifiers as `SpkrLeft2`/`SpkrRight2` on their own ports
(`<4 5 6 7>`, driven by the macros' second output, as on the CRD);
[`-14-speakers-shared.dts`](../dts/src/x1e80100-samsung-galaxy-book4-edge-14-speakers-shared.dts)
gives them the same ports as their partner (`<1 2 3 7>`). Install either with
`install/speakers-dtb.sh` (`SPEAKERS_DTB=...`); scripts in
[`tools/audio`](../tools/audio).

- **Mapping.** Raw PCM channel 1 → WSA2 RX0 → `SpkrRight` (bus 4, addr 2) →
  **left** side; channel 2 → WSA RX0 → `SpkrLeft` (bus 1, addr 2) → **right**
  side. The DT names are swapped. Channels 3/4 reach the macros' RX1
  (proved by routing RX1 into RX0).
- **Which is which.** With shared ports, a tone ladder (150 Hz–8 kHz) per pair:
  the original pair is heard from 300 Hz, the new pair only from 600 Hz. So
  Linux has always driven the **woofers**; the address-1 amps are the
  **tweeters**.
- **Shared ports work** (all four play) but each tweeter gets the woofer's
  full-range signal, bass included. Not safe as a default at high volume.
- **Own ports (`<4 5 6 7>`) do not work yet**: amps bind, DAPM is fully up,
  master port 4 and the amps' DP1/DP2 are enabled, yet the tweeters only hiss.
  The macros' SPK2 output (RX1) appears to carry no data on the bus.
- Windows (`qcaudminiportnx_extension8380.inf`): `MapSpkrStereoChToQuadDevices=1`,
  `SpeakerInternalChannelMapping` with 4 channels; i.e. stereo is fanned out
  to the four amps, probably with crossover/EQ in the DSP (Dolby).

Next: find why RX1 → SPK2 on port 4 is silent, then a 4-amp UCM profile with
a PipeWire crossover (highs only to the tweeters).

Testing a profile without installing it:

    systemctl --user set-environment ALSA_CONFIG_UCM2=/path/to/ucm2-copy
    systemctl --user restart wireplumber pipewire pipewire-pulse
    # WIREPLUMBER_DEBUG=spa.alsa:4 shows why a profile is rejected
