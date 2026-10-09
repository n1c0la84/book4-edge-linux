#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Test DTB with two 14" (NP940XMA) cleanups, as two patches:
# 0005 woofer names by side; 0006 the eUSB2 repeater at I2C 5 / 0x43 off
# (not in Windows' DSDT, nothing uses it; the 0x4f one serves usb_2). The shared
# x1e-samsung-galaxy-book4-edge.dtsi names the woofer on SoundWire 0 (WSA
# macro) "SpkrLeft", but it is the right woofer (docs/audio.md); the 14"
# board file overrides the two prefixes and the two audio-routing sinks.
# Routing and channels are unchanged: only ALSA control names swap. The
# 16" keeps the dtsi names (its wiring is not known).
#
# Commits on tmp/woofer-names from book4/7.2, writes the commit as
# dts/patches/0005-*.patch into this system's clone of the repo, builds the
# DTB, installs it padded as /boot/dtb-test/woofer-names.dtb and makes it the
# GRUB "alt DT" entry (Fedora kernel). Normal entries unchanged. Run in
# Fedora or through install/arch/fedora-shell.sh (sudo asks the Fedora
# password). Undo: sudo rm /etc/book4/test-dtb and rerun the hook.
set -euo pipefail
export GIT_PAGER=cat
REPO=$(cd "$(dirname "$0")/../.." && pwd)
TREE=${TREE:-$HOME/src/patchwork}
REF=${REF:-book4/7.2}
BR=tmp/woofer-names
D=arch/arm64/boot/dts/qcom
DTS=$D/x1e80100-samsung-galaxy-book4-edge-14.dts
DTB=x1e80100-samsung-galaxy-book4-edge-14.dtb
HOOK=/etc/kernel/install.d/99-book4-devicetree.install
K=$(cat /etc/book4/default-kernel)
cd "$TREE"
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "Uncommitted changes in $TREE." >&2; exit 1; }
start=$(git branch --show-current)
trap 'git switch -q "$start"' EXIT

echo "== 1. $BR from $REF"
git switch -q -C "$BR" "$REF"
python3 - "$DTS" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = '"SpkrLeft IN", "WSA WSA_SPK1 OUT"'
b = '"SpkrRight IN", "WSA2 WSA_SPK1 OUT"'
assert s.count(a) == 1 and s.count(b) == 1, "audio-routing lines not found"
s = s.replace(a, '@A@').replace(b, '@B@')
s = s.replace('@A@', '"SpkrRight IN", "WSA WSA_SPK1 OUT"')
s = s.replace('@B@', '"SpkrLeft IN", "WSA2 WSA_SPK1 OUT"')
s = s.rstrip('\n') + '''

/*
 * The woofer names in the shared dtsi are swapped on this model: the
 * amplifier on SoundWire 0 (WSA macro) drives the right woofer, the one on
 * SoundWire 3 (WSA2 macro) the left woofer, next to the tweeters of the same
 * side. Name them by side, like the tweeters. The labels stay as in the dtsi.
 */
&left_spkr {
	sound-name-prefix = "SpkrRight";
};

&right_spkr {
	sound-name-prefix = "SpkrLeft";
};
'''
open(p, 'w').write(s)
PY
git commit -q -a -F - <<'MSG'
arm64: dts: qcom: x1e80100-samsung-galaxy-book4-edge-14: name woofers by side

The shared Galaxy Book4 Edge dtsi calls the woofer amplifier on SoundWire 0
(WSA macro) "SpkrLeft" and the one on SoundWire 3 (WSA2 macro) "SpkrRight".
On the 14" (NP940XMA) they are the other way round: each SoundWire bus drives
the woofer and the tweeter of one side, and the tweeters are already named
by side. Override the two prefixes and the matching audio-routing sinks.
Only the ALSA control names change; the routing and channel order do not.
MSG
cat >> "$DTS" <<'DT'

/*
 * Only the eUSB2 repeater at 0x4f (usb_2, the fingerprint reader) exists on
 * this model; the firmware describes nothing at 0x43.
 */
&eusb5_repeater {
	status = "disabled";
};
DT
git commit -q -a -F - <<'MSG'
arm64: dts: qcom: x1e80100-samsung-galaxy-book4-edge-14: disable eusb5 repeater

The shared dtsi enables a PTN3222 eUSB2 repeater at 0x43 on I2C 5 next to
the one at 0x4f. On the 14" (NP940XMA) only the 0x4f repeater exists: it
serves usb_2 (the fingerprint reader). The ACPI tables describe no device
at 0x43 and no PHY references this node. Disable it.
MSG
git log --oneline -2
mkdir -p "$REPO/dts/patches"
git format-patch -q -2 --start-number 5 -o "$REPO/dts/patches"
ls "$REPO"/dts/patches/000[56]-*

echo "== 2. build the DTB"
make -s LOCALVERSION= olddefconfig >/dev/null
make -s LOCALVERSION= "qcom/$DTB"
dtc -q -I dtb -O dts "$D/$DTB" 2>/dev/null | grep -E 'sound-name-prefix = "(Spkr|Tweeter)' | sort | uniq -c
dtc -q -I dtb -O dts "$D/$DTB" 2>/dev/null | grep -A12 'redriver@43' | grep -E 'redriver|status'

echo "== 3. install as /boot/dtb-test/woofer-names.dtb (padded for GRUB)"
sudo -v
sudo mkdir -p /boot/dtb-test
sudo dtc -q -I dtb -O dtb -p 8192 -o /boot/dtb-test/woofer-names.dtb "$D/$DTB"
echo "/dtb-test/woofer-names.dtb" | sudo tee /etc/book4/test-dtb >/dev/null

echo "== 4. GRUB entry through the boot hook"
sudo "$HOOK" add "$K"
sudo grep -c cutmem /boot/efi/EFI/fedora/grub.cfg
sudo grep -E '^menuentry' /boot/efi/EFI/fedora/grub.cfg
echo
echo "Reboot, pick \"Fedora Linux ($K) - alt DT woofer-names.dtb\", then:"
echo "  amixer -c0 scontrols | grep -E 'Spkr|Tweeter' | grep 'PA Volume'"
echo "  speaker-test -c2 -t wav -l1     (\"Front Left\" must still come from the left)"
echo "  lsusb | grep 1c7a                (fingerprint reader still there)"
