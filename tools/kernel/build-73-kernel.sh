#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the 7.3 kernel: our fork's branch book4/7.3 (Anatase's 7.3.4 `anatase`
# + our patches, docs/ROADMAP.md item 4) and install it NEXT TO the daily
# 7.2.7-book4s, with its own release name, modules, initramfs and DTB, as the
# GRUB entry "... - test: el2-73" (EL2, like the daily one). Nothing of the
# daily kernel is replaced. Same build environment as build-sleep-kernel.sh:
# the Fedora container, the tree in Fedora's home (~/src/linux-73).
#
#   bash tools/kernel/build-73-kernel.sh            build + install + entry
#   bash tools/kernel/build-73-kernel.sh undo       remove entry, files, modules
#
# Config: the 7.2 sleep kernel's .config (~/src/patchwork-sleep/.config) run
# through olddefconfig, plus the options build-sleep-kernel.sh enforces. New
# 7.3 options take their defaults. The out-of-tree sleep modules (el1tmr,
# aoss_cxsd_only, cntv_arm, icc_hold, ...) are built for it too, so
# book4-el2-sleep.service runs on it.
#
# Boot it: reboot normally (the firmware's EL2 entry), pick "... - test:
# el2-73" in GRUB. If it does not come up, hold power: the next boot is the
# daily entry. Then: tools/kernel/check-73.sh (what to look at).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
# The release suffix comes from CONFIG_LOCALVERSION="-book4" (set below);
# LOCALVERSION stays empty, or the name doubles (7.3.4-book4-book4).
lv=
dtbname=x1e80100-samsung-galaxy-book4-edge-14.dtb
DEV_ROOT=/dev/disk/by-uuid/4d74e1d5-7bca-48bf-a6e0-1362fd77882e
name=el2-73
relfile=$HOME/.cache/book4/kernel-73.release
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
if findmnt -rn -S /dev/sda4 >/dev/null; then echo "error: /dev/sda4 (/boot) is mounted; unmount it first" >&2; exit 1; fi
if findmnt -rn -O ro /mnt/fedora/home >/dev/null; then echo "error: /mnt/fedora/home is mounted read-only; unmount it first" >&2; exit 1; fi

if [ "${1:-}" = undo ]; then
    rel=$(cat "$relfile" 2>/dev/null || true)
    [ -n "$rel" ] || { echo "nothing recorded in $relfile" >&2; exit 1; }
    [ "$(uname -r)" != "$rel" ] || { echo "error: $rel is running; boot the daily entry first" >&2; exit 1; }
    sudo -v
    bash "$repo/install/arch/test-entry.sh" remove $name || true
    b=$(mktemp -d); sudo mount /dev/sda4 "$b"
    sudo rm -f "$b/vmlinuz-$rel" "$b/initramfs-$rel-arch.img" "$b/dtb-test/book4-73.dtb" "$b/dtb-test/book4-73-el2.dtb"
    sync; sudo umount "$b"; rmdir "$b"
    case $rel in 7.3*) sudo rm -rf --one-file-system "/usr/lib/modules/$rel" ;; esac
    rm -f "$relfile"; echo "removed $rel"; exit 0
fi

# keep sudo alive through the long build (one password at the start)
sudo -v
( while sleep 50; do sudo -n -v 2>/dev/null || exit; done ) &
KEEPALIVE=$!
trap 'kill $KEEPALIVE 2>/dev/null || true' EXIT
echo "== 0. sleep modules for the container"
pay=$(mktemp -d)
tar -cz --exclude='*.ko' --exclude='*.o' --exclude='*.mod*' --exclude='.*' \
    -C "$repo/tools/power" -f "$pay/mods.tgz" sleep-modules icc-hold/icc_hold.c
fh=$(mktemp -d); sudo mount -o subvol=home "$DEV_ROOT" "$fh"
sudo install -d -m 755 "$fh/$USER/src/.book4-build"
sudo install -m 644 "$pay/mods.tgz" "$fh/$USER/src/.book4-build/mods-73.tgz"
sync; sudo umount "$fh"; rmdir "$fh"; rm -rf "$pay"

echo "== 1. build in the Fedora container (~/src/linux-73)"
inner="set -euo pipefail
cd ~/src
if [ ! -d linux-73/.git ]; then
    git clone -q --filter=blob:none -b book4/7.3 https://github.com/n1c0la84/linux-book4-edge.git linux-73
fi
cd linux-73
git fetch -q origin book4/7.3
git checkout -q -B book4/7.3 origin/book4/7.3
# Anatase's drivers/custom/ are git submodules (evdi, xone, ...); Kconfig
# sources them, so they must be present even when not built.
git submodule update -q --init --depth 1 >&2
echo \"   tree: \$(git log -1 --format='%h %s')\" >&2
[ -e .config ] || cp ~/src/patchwork-sleep/.config .config
./scripts/config --set-str LOCALVERSION -book4 --disable LOCALVERSION_AUTO
make -s LOCALVERSION=$lv olddefconfig
for o in PM_CLK QCOM_TZMEM_MODE_SHMBRIDGE CPU_IDLE_GOV_TEO; do
    grep -q \"^CONFIG_\$o=y\" .config || { ./scripts/config --enable \$o; make -s LOCALVERSION=$lv olddefconfig; }
done
./scripts/config --disable QCOM_TZMEM_MODE_GENERIC
for o in QCOM_SCMI_GENERIC_EXT DEVFREQ_GOV_REMOTE SCMI_QCOM_MEMLAT_DEVFREQ SM_VIDEOCC_8550 VIDEO_QCOM_IRIS TYPEC_SAMSUNG_EMUEC EC_SAMSUNG_GALAXYBOOK RPMSG_QCOM_GLINK_SPSS QCOM_SPSS_NVM TCG_QCOM_SPSS; do
    grep -q \"^CONFIG_\$o=[ym]\" .config || ./scripts/config --module \$o
done
make -s LOCALVERSION=$lv olddefconfig
for o in PM_CLK QCOM_TZMEM_MODE_SHMBRIDGE CPU_IDLE_GOV_TEO; do grep -q \"^CONFIG_\$o=y\" .config || { echo \"error: CONFIG_\$o not set\" >&2; exit 1; }; done
rel=\$(make -s LOCALVERSION=$lv kernelrelease)
echo \"   release \$rel\" >&2
make -s -j\$(nproc) LOCALVERSION=$lv Image modules qcom/$dtbname >&2
out=~/src/out-73; rm -rf \$out; mkdir -p \$out
make -s LOCALVERSION=$lv INSTALL_MOD_PATH=\$out INSTALL_MOD_STRIP=1 DEPMOD=true modules_install >&2
m=\$(mktemp -d); tar -xzf ~/src/.book4-build/mods-73.tgz -C \$m
cp \$m/icc-hold/icc_hold.c \$m/sleep-modules/; echo 'obj-m += icc_hold.o' >> \$m/sleep-modules/Makefile
make -s LOCALVERSION=$lv M=\$m/sleep-modules modules >&2 || echo '   WARNING: sleep modules did not build for 7.3' >&2
install -D -m 644 -t \$out/lib/modules/\$rel/extra \$m/sleep-modules/*.ko 2>/dev/null || true
rm -f \$out/lib/modules/\$rel/build \$out/lib/modules/\$rel/source
cp arch/arm64/boot/Image arch/arm64/boot/dts/qcom/$dtbname \$out/
echo \$rel > \$out/release
echo \"   modules: \$(find \$out/lib/modules/\$rel -name '*.ko*' | wc -l), extra: \$(ls \$out/lib/modules/\$rel/extra 2>/dev/null | tr '\\n' ' ')\" >&2"
systemd-inhibit --what=sleep:idle:handle-lid-switch --why="kernel build" \
    bash "$repo/install/arch/fedora-shell.sh" bash -lc "$inner"

echo "== 2. install on Arch"
sudo -v
h=$(mktemp -d); sudo mount -o ro,subvol=home "$DEV_ROOT" "$h"
src=$h/$USER/src/out-73
rel=$(cat "$src/release")
case $rel in 7.3*) ;; *) sudo umount "$h"; echo "error: unexpected release '$rel'" >&2; exit 1 ;; esac
[ "$(uname -r)" != "$rel" ] || { sudo umount "$h"; echo "error: $rel is running; boot the daily entry to reinstall it" >&2; exit 1; }
work=$(mktemp -d); trap 'rm -rf "$work"; kill $KEEPALIVE 2>/dev/null || true' EXIT
# A previous install under another release name (7.3.4-book4-book4): remove it.
old=$(cat "$relfile" 2>/dev/null || true)
if [ -n "$old" ] && [ "$old" != "$rel" ]; then
    case $old in 7.3*) ;; *) old= ;; esac
    [ "$(uname -r)" != "$old" ] || { sudo umount "$h"; echo "error: $old is running; boot the daily entry first" >&2; exit 1; }
    if [ -n "$old" ]; then
        echo "   removing the previous install $old"
        sudo rm -rf --one-file-system "/usr/lib/modules/$old"
        ob=$(mktemp -d); sudo mount /dev/sda4 "$ob"
        sudo rm -f "$ob/vmlinuz-$old" "$ob/initramfs-$old-arch.img"
        sync; sudo umount "$ob"; rmdir "$ob"
    fi
fi
sudo rm -rf "/usr/lib/modules/$rel"
sudo cp -a "$src/lib/modules/$rel" "/usr/lib/modules/$rel"
cp "$src/Image" "$src/$dtbname" "$work/"
sudo umount "$h"; rmdir "$h"
sudo depmod "$rel"
mkdir -p "$(dirname "$relfile")"; echo "$rel" > "$relfile"
echo "   /usr/lib/modules/$rel: $(find /usr/lib/modules/$rel -name '*.ko*' | wc -l) modules"
sudo mkinitcpio -k "$rel" -g "$work/initramfs.img" >/dev/null 2>&1 || true
sudo chmod 644 "$work/initramfs.img"
LIST=$(lsinitcpio "$work/initramfs.img")
grep -qE '/ufs-qcom\.ko' <<<"$LIST" || { echo "error: ufs-qcom.ko missing from the initramfs" >&2; exit 1; }
b=$(mktemp -d); sudo mount /dev/sda4 "$b"
sudo install -m 644 "$work/Image" "$b/vmlinuz-$rel"
sudo install -m 644 "$work/initramfs.img" "$b/initramfs-$rel-arch.img"
sudo install -m 644 "$work/$dtbname" "$b/dtb-test/book4-73.dtb"
sudo rm -f "$b/dtb-test/book4-73-el2.dtb"
sync; df -h "$b" | tail -1; sudo umount "$b"; rmdir "$b"

echo "== 3. GRUB entry '$name' (EL2 DTB from install/el2/el2-dtb.sh)"
bash "$repo/install/arch/test-entry.sh" remove $name >/dev/null 2>&1 || true
bash "$repo/install/el2/el2-dtb.sh" /dtb-test/book4-73.dtb $name -clk_ignore_unused -pd_ignore_unused \
    "kernel=/vmlinuz-$rel" "initrd=/initramfs-$rel-arch.img"
echo
echo "Installed $rel as '... - test: $name'. Reboot normally (EL2 chain) and pick it in GRUB."
