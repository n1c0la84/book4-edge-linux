#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Test kernel 7.2.7-book4s with everything known to stand between X1E and
# full s2idle deep sleep (docs/power.md, 19 October): the 7.3 PDC series and
# domain_ss3, DRIPS for system sleep only plus SS1 for runtime idle, the 7.3
# LPASS macro and geni serial fixes, the syscon XO fix, and the Book4 panel
# supplies no longer always-on (tools/kernel/sleep-backport/, branch
# book4/7.2-sleep in n1c0la84/linux-book4-edge). Out-of-tree modules from
# tools/power/sleep-modules (cntv_arm, el1tmr, qcom_adsp_pwr_lmts, aoss_cxsd_only)
# and icc_hold are built for it and installed under extra/.
#
# Its own release name, so its modules and initramfs are separate and the
# normal 7.2.7-book4 is not touched:
#   1. Fedora container: reflink copy ~/src/patchwork -> ~/src/patchwork-sleep
#      (a new patch set makes a fresh copy), patch, build Image, modules and
#      the 14" DTB with LOCALVERSION=s, modules_install into ~/src/sleep-out.
#   2. Arch: copy the modules to /usr/lib/modules/7.2.7-book4s, depmod,
#      mkinitcpio; install /vmlinuz-7.2.7-book4s,
#      /initramfs-7.2.7-book4s-arch.img and /dtb-test/book4-sleep.dtb on /boot.
#   3. install/el2/sleep-setup.sh then makes the EL2 entry from that DTB
#      (no EL1 entry for this kernel any more: it is the EL2 kernel).
#
#   bash tools/kernel/build-sleep-kernel.sh
#
# Undo: install/el2/sleep-setup.sh undo; then, if you like,
# sudo rm -r /usr/lib/modules/7.2.7-book4s and the three files on /boot.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
base=7.2.7-book4
lv=s
rel=$base$lv
dtbname=x1e80100-samsung-galaxy-book4-edge-14.dtb
DEV_ROOT=/dev/disk/by-uuid/4d74e1d5-7bca-48bf-a6e0-1362fd77882e   # btrfs (sda5): root, home, arch

[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
if findmnt -rn -O ro /mnt/fedora/home >/dev/null; then
    echo "error: /mnt/fedora/home is mounted read-only; unmount it first (the container needs it read-write)" >&2; exit 1
fi
if findmnt -rn -S /dev/sda4 >/dev/null; then
    echo "error: /dev/sda4 (/boot) is mounted; unmount it first" >&2; exit 1
fi
for t in dtc mkinitcpio lsinitcpio; do command -v $t >/dev/null || { echo "error: $t missing" >&2; exit 1; }; done
# kernel-modules-hook's boot-time cleanup deletes module trees pacman doesn't
# own unless they belong to the running kernel (stage3-omarchy-install.sh).
case "$(systemctl is-enabled linux-modules-cleanup.service 2>/dev/null || true)" in
    masked|not-found|"") ;;
    *) echo "error: linux-modules-cleanup.service is active and would delete this kernel's modules at the next boot of another kernel; run: sudo systemctl mask linux-modules-cleanup.service" >&2; exit 1 ;;
esac
[ "$(uname -r)" != "$rel" ] || { echo "error: running $rel itself; boot the normal kernel to rebuild it" >&2; exit 1; }

patches=$(tar -cz -C "$here/sleep-backport" $(cd "$here/sleep-backport" && ls *.patch) | base64 -w0)
emuec=$(tar -cz -C "$repo/drivers/anatase" --transform 's|^patches|emuec|' patches | base64 -w0)
# the whole sleep-modules folder (every source the Makefile names) + icc_hold
mods=$(tar -cz --exclude='*.ko' --exclude='*.o' --exclude='*.mod*' --exclude='.*' \
       -C "$repo/tools/power" sleep-modules icc-hold/icc_hold.c | base64 -w0)
sum=$(cat "$here"/sleep-backport/*.patch | sha256sum | cut -c1-16)
# Checksum of every prefix of the set, "N:sum" for the first N patches: a tree
# built with the first N patches only needs patches N+1.. applied (patches
# added at the end, 21 October), not a fresh copy and a full rebuild.
prefixes=$(i=0; for f in "$here"/sleep-backport/*.patch; do i=$((i + 1));
    printf '%s:%s ' $i "$(ls "$here"/sleep-backport/*.patch | head -$i | xargs cat | sha256sum | cut -c1-16)"; done)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

echo "== 1. build $rel in the Fedora container (~/src/patchwork-sleep)"
inner="set -euo pipefail
cd ~/src
have=0
if [ -e patchwork-sleep ]; then
    rec=\$(cat patchwork-sleep/.book4-patches 2>/dev/null || true)
    for ps in $prefixes; do [ \"\${ps#*:}\" = \"\$rec\" ] && have=\${ps%%:*}; done
    if [ \$have = 0 ]; then
        echo '   patch set changed: fresh copy of ~/src/patchwork' >&2
        rm -rf patchwork-sleep
    fi
fi
if [ ! -e patchwork-sleep ]; then
    echo '   reflink copy ~/src/patchwork -> ~/src/patchwork-sleep' >&2
    cp -a --reflink=always patchwork patchwork-sleep
    cd patchwork-sleep
    r=\$(make -s LOCALVERSION= kernelrelease)
    [ \"\$r\" = $base ] || { echo \"error: tree release is \$r, expected $base\" >&2; exit 1; }
    p=\$(mktemp -d); echo $patches | base64 -d | tar -xz -C \$p
    for f in \$p/*.patch; do
        patch -p1 --forward -s < \$f >&2 || { echo \"error: \$(basename \$f) does not apply\" >&2; exit 1; }
        echo \"   applied: \$(basename \$f)\" >&2
    done
    # samsung-emuec patches (drivers/anatase/patches): ~/src/patchwork got
    # them only as a module build, never in its source, so a copy lacks them
    # (22 October: unplug-during-sleep reset back at EL2)
    echo $emuec | base64 -d | tar -xz -C \$p
    for f in \$p/emuec/*.patch; do
        patch -s -p1 -d drivers/usb/typec --dry-run -R -f -i \$f >/dev/null 2>&1 && continue
        patch -s -p1 -d drivers/usb/typec -f -i \$f >&2 || { echo \"error: \$(basename \$f) does not apply\" >&2; exit 1; }
        echo \"   applied: \$(basename \$f) (samsung-emuec)\" >&2
    done
    rm -f drivers/usb/typec/samsung-emuec.c.orig
    echo $sum > .book4-patches
else
    cd patchwork-sleep
    p=\$(mktemp -d); echo $patches | base64 -d | tar -xz -C \$p
    i=0
    for f in \$p/*.patch; do
        i=\$((i + 1)); [ \$i -gt \$have ] || continue
        patch -p1 --forward -s < \$f >&2 || { echo \"error: \$(basename \$f) does not apply\" >&2; exit 1; }
        echo \"   applied (incremental): \$(basename \$f)\" >&2
    done
    [ \$i -gt \$have ] || echo '   patches already applied (same set)' >&2
    echo $sum > .book4-patches
fi
[ \"\$(make -s LOCALVERSION=$lv kernelrelease)\" = $rel ]
grep -q 'pm: quiesced' drivers/usb/typec/samsung-emuec.c || { echo 'error: samsung-emuec has no sleep quiesce: run tools/kernel/update-sleep-emuec.sh' >&2; exit 1; }
grep -q '^CONFIG_PM_CLK=y' .config || { echo 'error: CONFIG_PM_CLK is off: the LPASS macros would not build' >&2; exit 1; }
# TrustZone buffers through SHM bridges (20 October): at EL2 there is no
# Gunyah to share memory with TrustZone, and qseecom's first call (the
# uefisecapp lookup) is refused with -22, hence no EFI variables. The
# allocator falls back to the generic mode if TrustZone has no SHM bridge.
if ! grep -q '^CONFIG_QCOM_TZMEM_MODE_SHMBRIDGE=y' .config; then
    ./scripts/config --disable QCOM_TZMEM_MODE_GENERIC --enable QCOM_TZMEM_MODE_SHMBRIDGE
    make -s LOCALVERSION=$lv olddefconfig
    echo '   config: QCOM_TZMEM_MODE_SHMBRIDGE' >&2
fi
grep -q '^CONFIG_QCOM_TZMEM_MODE_SHMBRIDGE=y' .config || { echo 'error: could not set CONFIG_QCOM_TZMEM_MODE_SHMBRIDGE' >&2; exit 1; }
make -s -j\$(nproc) LOCALVERSION=$lv Image modules qcom/$dtbname >&2
out=~/src/sleep-out; rm -rf \$out; mkdir -p \$out
make -s LOCALVERSION=$lv INSTALL_MOD_PATH=\$out INSTALL_MOD_STRIP=1 DEPMOD=true modules_install >&2
m=\$(mktemp -d); echo $mods | base64 -d | tar -xz -C \$m
cp \$m/icc-hold/icc_hold.c \$m/sleep-modules/; echo 'obj-m += icc_hold.o' >> \$m/sleep-modules/Makefile
make -s LOCALVERSION=$lv M=\$m/sleep-modules modules >&2
install -D -m 644 -t \$out/lib/modules/$rel/extra \$m/sleep-modules/*.ko
rm -f \$out/lib/modules/$rel/build \$out/lib/modules/$rel/source
cp arch/arm64/boot/Image arch/arm64/boot/dts/qcom/$dtbname \$out/
echo \"   modules: \$(find \$out/lib/modules/$rel -name '*.ko*' | wc -l), extra: \$(ls \$out/lib/modules/$rel/extra | tr '\\n' ' ')\" >&2"
# no suspend while building (a lid close would interrupt the container)
systemd-inhibit --what=sleep:idle:handle-lid-switch --why="kernel build" \
    bash "$repo/install/arch/fedora-shell.sh" bash -lc "$inner"

echo "== 2. install on Arch"
sudo -v
h=$(mktemp -d); sudo mount -o ro,subvol=home "$DEV_ROOT" "$h"
src=$h/$USER/src/sleep-out
[ -d "$src/lib/modules/$rel/kernel" ] && [ -s "$src/Image" ] || { sudo umount "$h"; echo "error: no build output in $src" >&2; exit 1; }
sudo rm -rf /usr/lib/modules/$rel.new
sudo cp -a "$src/lib/modules/$rel" /usr/lib/modules/$rel.new
cp "$src/Image" "$src/$dtbname" "$work/"
sudo umount "$h"; rmdir "$h"
sudo rm -rf /usr/lib/modules/$rel
sudo mv /usr/lib/modules/$rel.new /usr/lib/modules/$rel
sudo depmod $rel
echo "   /usr/lib/modules/$rel: $(find /usr/lib/modules/$rel -name '*.ko*' | wc -l) modules"
sudo mkinitcpio -k $rel -g "$work/initramfs.img" >/dev/null
LIST=$(sudo lsinitcpio "$work/initramfs.img")   # captured: grep -q in a pipe trips pipefail
grep -qE '/ufs-qcom\.ko(\.[gx]z|\.zst)?$' <<<"$LIST" || { echo "error: ufs-qcom.ko missing from the initramfs" >&2; exit 1; }
dtc -q -I dtb -O dtb -p 8192 -o "$work/book4-sleep.dtb" "$work/$dtbname"   # padded for GRUB
DTS=$(dtc -q -I dtb -O dts "$work/book4-sleep.dtb")
grep -c 'system-sleep-only' <<<"$DTS" >/dev/null || { echo "error: DTB has no system-sleep-only DRIPS" >&2; exit 1; }
grep -c 'arm,psci-suspend-param = <0x2000154>' <<<"$DTS" >/dev/null || { echo "error: DTB has no SS1" >&2; exit 1; }

b=$(mktemp -d); sudo mount /dev/sda4 "$b"
sudo install -m 644 "$work/Image" "$b/vmlinuz-$rel"
sudo install -m 644 "$work/initramfs.img" "$b/initramfs-$rel-arch.img"
sudo mkdir -p "$b/dtb-test"; sudo install -m 644 "$work/book4-sleep.dtb" "$b/dtb-test/book4-sleep.dtb"
sync; ls -l "$b/vmlinuz-$rel" "$b/initramfs-$rel-arch.img" "$b/dtb-test/book4-sleep.dtb"
sudo umount "$b"; rmdir "$b"

echo
echo "Installed $rel. Refresh the daily EL2 entry from the new DTB:"
echo "  bash install/el2/sleep-setup.sh"
