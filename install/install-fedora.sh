#!/bin/bash
# Install the Galaxy Book4 Edge 14" support onto a Fedora (aarch64) system that
# already boots (see docs/bootstrap.md for getting that far).
#
# Every step below was tested individually on a 14" NP940XMA with Fedora 45 /
# kernel 7.2.0-61. The script as a whole has NOT yet been run end to end.
#
#   bash install/install-fedora.sh [BT_ADDRESS]
#
# BT_ADDRESS: the Bluetooth address to use (e.g. from
# tools/bt-address-from-windows.py). Without it the Bluetooth step is skipped.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
K=$(uname -r)
BT=${1:-}
FWDIR=/usr/lib/firmware/qcom/x1e80100/SAMSUNG/galaxy-book4-edge
DTB=x1e80100-samsung-galaxy-book4-edge-14.dtb
sudo -v

step() { printf '\n== %s\n' "$*"; }

step "checks"
for f in qcadsp8380.mbn adsp_dtbs.elf qccdsp8380.mbn cdsp_dtbs.elf qcdxkmsuc8380.mbn; do
    [ -e "$FWDIR/$f" ] || [ -e "$FWDIR/$f.xz" ] || { echo "missing $FWDIR/$f - see docs/firmware.md"; exit 1; }
done
[ -L /lib ] || echo "note: /lib is not a symlink here; paths below use /usr/lib explicitly"

step "packages"
sudo dnf install -y dkms "kernel-devel-$K" gcc make patch

step "DSP firmware into the initramfs, keyboard fix, no ghost battery"
sudo install -D -m 644 "$REPO/userspace/dracut/book4-fw.conf"            /etc/dracut.conf.d/book4-fw.conf
sudo install -D -m 644 "$REPO/userspace/keyboard/99-book4-keyboard.rules" /etc/udev/rules.d/99-book4-keyboard.rules
sudo install -D -m 644 "$REPO/userspace/modprobe/book4-no-battmgr.conf"   /etc/modprobe.d/book4-no-battmgr.conf

step "device tree + boot hook (keeps the static grub.cfg in sync with installed kernels)"
sudo install -D -m 644 "$REPO/dts/x1e80100-samsung-galaxy-book4-edge-14.anatase.dtb" /usr/lib/firmware/book4/$DTB
sudo install -D -m 755 "$REPO/userspace/boot/99-book4-devicetree.install" /etc/kernel/install.d/99-book4-devicetree.install
sudo install -d /etc/book4
[ -e /etc/book4/default-kernel ] || echo "$K" | sudo tee /etc/book4/default-kernel >/dev/null
grep -q mem_sleep_default /etc/kernel/cmdline 2>/dev/null || \
    sudo sed -i 's/$/ mem_sleep_default=s2idle/' /etc/kernel/cmdline
grep -q 'cma=256M' /etc/kernel/cmdline || echo "WARNING: cma=256M missing from /etc/kernel/cmdline (needed by ath12k)"

step "drivers via DKMS (Anatase battery + Type-C, with our patches)"
SRC=/usr/src/book4-edge-anatase-1.1
sudo rm -rf "$SRC"; sudo install -d "$SRC"
sudo install -m 644 "$REPO"/drivers/anatase/{ene-kb9058-battery.c,samsung-emuec.c,Makefile,dkms.conf} "$SRC/"
for p in "$REPO"/drivers/anatase/patches/*.patch; do sudo patch -d "$SRC" -p1 -i "$p"; done
sudo dkms remove book4-edge-anatase/1.1 --all 2>/dev/null || true
sudo dkms add book4-edge-anatase/1.1
sudo dkms install book4-edge-anatase/1.1 -k "$K"   # also regenerates the initramfs

step "audio: topology name + UCM profile"
U=/usr/lib/firmware/updates/qcom/x1e80100
sudo install -d $U
sudo ln -sfn ../../../qcom/x1e80100/X1E80100-CRD-tplg.bin.xz $U/X1E80100-GalaxyBook4Edge-tplg.bin.xz
sudo install -m 644 "$REPO"/userspace/audio/ucm2/*.conf /usr/share/alsa/ucm2/Qualcomm/x1e80100/
# UCM finds profiles by the card long name, which ASoC builds from DMI as
# vendor-product-version-board (spaces and commas dropped, '-' -> '_').
dmi() { tr -d ' ,\n' < /sys/devices/virtual/dmi/id/$1 | tr - _; }
LONG="$(dmi sys_vendor)-$(dmi product_name)-$(dmi product_version)-$(dmi board_name)"
echo "card long name: $LONG"
sudo ln -sfn ../../Qualcomm/x1e80100/Samsung-GalaxyBook4Edge.conf \
    "/usr/share/alsa/ucm2/conf.d/x1e80100/$LONG.conf"

step "Bluetooth address"
if [ -n "$BT" ]; then
    echo "$BT" | sudo tee /etc/book4/bt-address >/dev/null
    sudo install -m 755 "$REPO/userspace/bluetooth/book4-bt-addr" /usr/local/sbin/book4-bt-addr
    sudo install -m 644 "$REPO/userspace/bluetooth/book4-bt-addr.service" /etc/systemd/system/book4-bt-addr.service
    sudo systemctl daemon-reload
    sudo systemctl enable book4-bt-addr.service
else
    echo "skipped (no address given)"
fi

step "regenerate grub.cfg for $K"
sudo /etc/kernel/install.d/99-book4-devicetree.install add "$K"

step "done - reboot into the first menu entry"
