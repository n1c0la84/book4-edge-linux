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
-34 dBFS; the profile uses 120 (+36 dB, about -14 dBFS, no clipping, noise
floor about -46 dBFS). The enable sequences are inlined because an
`EnableSequence` placed after an `Include` of the stock one does not override
it.

Open question: each speaker bus also enumerates a second WSA883x at SoundWire
address 1 that no device tree describes. The machine may have four speakers.

Testing a profile without installing it:

    systemctl --user set-environment ALSA_CONFIG_UCM2=/path/to/ucm2-copy
    systemctl --user restart wireplumber pipewire pipewire-pulse
    # WIREPLUMBER_DEBUG=spa.alsa:4 shows why a profile is rejected
