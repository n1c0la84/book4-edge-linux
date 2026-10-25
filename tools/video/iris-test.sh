#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Iris hardware video decoder at EL2 (sleep-backport 0040 + the &iris part of
# dts/src/x1-el2-book4.dtso). The first start is done by hand: the module is
# blacklisted until it has worked once, so a hang or reset while the firmware
# starts cannot come back on every boot. Run as yourself on the EL2 boot:
#
#   bash tools/video/iris-test.sh hold    # before the reboot into the new kernel: no autoload
#   bash tools/video/iris-test.sh         # after it: modprobe, then H.264/HEVC decode tests
#   bash tools/video/iris-test.sh keep    # it works: autoload from now on
set -euo pipefail
conf=/etc/modprobe.d/book4-iris-hold.conf

case ${1:-test} in
hold)
    echo 'blacklist qcom_iris   # tools/video/iris-test.sh: first start by hand' | sudo tee $conf >/dev/null
    echo "qcom_iris will not autoload (until: bash $0 keep)"; exit 0 ;;
keep)
    sudo rm -f $conf; echo "qcom_iris autoloads from the next boot"; exit 0 ;;
test) ;;
*) echo "usage: $0 [hold|keep|test]" >&2; exit 2 ;;
esac

[ -e /dev/kvm ] || echo "warning: not at EL2 (no /dev/kvm); this path is for the EL2 boot" >&2
sudo -v
since=$(date '+%Y-%m-%d %H:%M:%S')
sync   # in case the firmware start takes the machine down
lsmod | grep -q '^videocc_sm8550' || sudo modprobe videocc_sm8550
lsmod | grep -q '^qcom_iris' || sudo modprobe qcom_iris
sleep 2
echo "== kernel log"
journalctl -k --since "$since" --no-pager -o cat | grep -iE 'iris|videocc|aa00000|aaf0000|smmu|vpu' || echo "   (nothing)"
echo "== devices"
v4l2-ctl --list-devices 2>/dev/null || true
ls -l /dev/video* 2>/dev/null || { echo "error: no /dev/video*" >&2; exit 1; }

# The firmware starts at the first open, not at probe.
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
ffmpeg -v error -f lavfi -i testsrc2=size=1920x1080:rate=60 -t 10 -c:v libx264 -preset veryfast -pix_fmt yuv420p "$work/h264.mp4"
ffmpeg -v error -f lavfi -i testsrc2=size=1920x1080:rate=60 -t 10 -c:v libx265 -preset veryfast -pix_fmt yuv420p -x265-params log-level=error "$work/hevc.mp4"
for c in h264 hevc; do
    echo "== $c 1080p60, 600 frames"
    for dec in ${c}_v4l2m2m sw; do
        args=(); [ $dec = sw ] || args=(-c:v $dec)
        t0=$(date +%s%N)
        if out=$(ffmpeg -hide_banner -nostats "${args[@]}" -i "$work/$c.mp4" -f null - 2>&1); then
            ms=$((($(date +%s%N) - t0) / 1000000))
            n=$(grep -oE 'frame= *[0-9]+' <<<"$out" | tail -1 | grep -oE '[0-9]+' || echo '?')
            printf '   %-14s %s frames in %d.%03d s\n' $dec "$n" $((ms / 1000)) $((ms % 1000))
        else
            echo "   $dec FAILED:"; tail -5 <<<"$out" | sed 's/^/      /'
        fi
    done
done
echo "== kernel log after decoding"
journalctl -k --since "$since" --no-pager -o cat | grep -iE 'iris|smmu|vpu|fault' | tail -20 || echo "   (nothing)"
