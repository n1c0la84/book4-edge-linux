#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# 7.3 microphone (18 November): the ADSP rejects GRAPH_START on
# VA_CODEC_DMA_TX_0 ("Failed to start APM port 110", APM error 1 on
# 0x01001002) on 7.3 with either DTB; 7.2 records fine. Same mixer path, same
# topology and UCM. This reverts a set of the 7.3-only sound/soc/qcom/qdsp6
# commits in the 7.3 tree (Fedora container, ~/src/linux-73, local branch
# audio-bisect), rebuilds only the qdsp6 modules and installs them under
# /usr/lib/modules/7.3.4-book4/updates (depmod prefers them). Reboot into
# 7.3 (test: 73-noctcu), then record: works = the cause is in the set.
#
#   bash tools/kernel/audio-bisect-73.sh all        revert every candidate
#   bash tools/kernel/audio-bisect-73.sh SHA...     revert only these
#   bash tools/kernel/audio-bisect-73.sh undo       drop the updates/ modules
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); repo=$(cd "$here/../.." && pwd)
rel=7.3.4-book4
DEV_ROOT=/dev/disk/by-uuid/4d74e1d5-7bca-48bf-a6e0-1362fd77882e
# 7.3-only qdsp6 commits, newest first (git log book4/7.3 -- sound/soc/qcom/qdsp6)
all="c8027dc991 1465af8fcc a2c410365b a99feace2d e564eef02b de31979f31 b009e247f2
     9c9fb79f97 4d08401758 67605cbf8d cc8495c1d4 c663014e45"
case ${1:?all, SHA... or undo} in
    undo) sudo rm -rf "/usr/lib/modules/$rel/updates/qdsp6-bisect"; sudo depmod "$rel"; echo "updates removed"; exit 0 ;;
    all) set -- $all ;;
esac
revs="$*"
if findmnt -rn -O ro /mnt/fedora/home >/dev/null; then echo "error: /mnt/fedora/home is mounted read-only; unmount it first" >&2; exit 1; fi
sudo -v
inner="set -euo pipefail
cd ~/src/linux-73
git checkout -q -B audio-bisect book4/7.3
for c in $revs; do
    git revert --no-edit \$c >/dev/null 2>&1 || { git revert --abort; echo \"   revert of \$c conflicts, skipped\" >&2; continue; }
    echo \"   reverted \$(git log -1 --format=%s | cut -c1-70)\" >&2
done
make -s LOCALVERSION= M=sound/soc/qcom/qdsp6 modules >&2
rm -rf ~/src/out-audio; mkdir -p ~/src/out-audio
cp sound/soc/qcom/qdsp6/*.ko ~/src/out-audio/
git checkout -q book4/7.3
echo \"   \$(ls ~/src/out-audio | wc -l) modules\" >&2"
bash "$repo/install/arch/fedora-shell.sh" bash -lc "$inner"
h=$(mktemp -d); sudo mount -o ro,subvol=home "$DEV_ROOT" "$h"
sudo rm -rf "/usr/lib/modules/$rel/updates/qdsp6-bisect"
sudo install -D -m 644 -t "/usr/lib/modules/$rel/updates/qdsp6-bisect" "$h/$USER/src/out-audio/"*.ko
sudo umount "$h"; rmdir "$h"
sudo depmod "$rel"
echo "Installed. Reboot into 7.3 (test: 73-noctcu), then: pw-record --target alsa_input.platform-sound.HiFi__Mic__source /tmp/m.wav (3 s), and journalctl -k | grep 'APM port'."
