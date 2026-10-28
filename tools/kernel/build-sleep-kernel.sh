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
#      mkinitcpio (when 7.2.7-book4s itself is running: staged in
#      /var/lib/book4/staged and swapped in at the next boot by
#      book4-modules-swap.service, so the running kernel's modules are never
#      replaced under it); install /vmlinuz-7.2.7-book4s,
#      /initramfs-7.2.7-book4s-arch.img and /dtb-test/book4-sleep.dtb on /boot.
#      The DTB gets dts/src/x1e80100-book4-edge-14-speakers.dtso first: the
#      tree is the Anatase base without dts/patches, so its DTB drove only
#      the woofers, swapped (28 October: "audio is very low").
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
for t in dtc fdtoverlay fdtget mkinitcpio lsinitcpio; do command -v $t >/dev/null || { echo "error: $t missing" >&2; exit 1; }; done
# kernel-modules-hook's boot-time cleanup deletes module trees pacman doesn't
# own unless they belong to the running kernel (stage3-omarchy-install.sh).
case "$(systemctl is-enabled linux-modules-cleanup.service 2>/dev/null || true)" in
    masked|not-found|"") ;;
    *) echo "error: linux-modules-cleanup.service is active and would delete this kernel's modules at the next boot of another kernel; run: sudo systemctl mask linux-modules-cleanup.service" >&2; exit 1 ;;
esac
# Running this kernel: its modules are staged and swapped in at the next boot
# (userspace/boot/book4-modules-swap), never replaced under the running kernel.
staged=; [ "$(uname -r)" != "$rel" ] || staged=1
stage=/var/lib/book4/staged

# The patches and module sources go to the container as files in Fedora's
# ~/src/.book4-build (as base64 in the command they outgrew the 128 KB limit
# for one argument, 23 October: "Argument list too long").
pay=$(mktemp -d)
tar -cz -C "$here/sleep-backport" -f "$pay/patches.tgz" $(cd "$here/sleep-backport" && ls *.patch)
tar -cz -C "$repo/drivers/anatase" --transform 's|^patches|emuec|' -f "$pay/emuec.tgz" patches
tar -cz -C "$repo/drivers/anatase" --transform 's|^patches-galaxybook-ec|gbec|' -f "$pay/gbec.tgz" patches-galaxybook-ec
# the whole sleep-modules folder (every source the Makefile names) + icc_hold
tar -cz --exclude='*.ko' --exclude='*.o' --exclude='*.mod*' --exclude='.*' \
    -C "$repo/tools/power" -f "$pay/mods.tgz" sleep-modules icc-hold/icc_hold.c
sudo -v
fh=$(mktemp -d); sudo mount -o subvol=home "$DEV_ROOT" "$fh"
sudo rm -rf "$fh/$USER/src/.book4-build"
sudo install -d -m 755 "$fh/$USER/src/.book4-build"
sudo install -m 644 "$pay"/*.tgz "$fh/$USER/src/.book4-build/"
sync; sudo umount "$fh"; rmdir "$fh"; rm -rf "$pay"
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
    p=\$(mktemp -d); tar -xzf ~/src/.book4-build/patches.tgz -C \$p
    for f in \$p/*.patch; do
        patch -p1 --forward -s < \$f >&2 || { echo \"error: \$(basename \$f) does not apply\" >&2; exit 1; }
        echo \"   applied: \$(basename \$f)\" >&2
    done
    # samsung-emuec patches (drivers/anatase/patches): ~/src/patchwork got
    # them only as a module build, never in its source, so a copy lacks them
    # (22 October: unplug-during-sleep reset back at EL2)
    tar -xzf ~/src/.book4-build/emuec.tgz -C \$p
    for f in \$p/emuec/*.patch; do
        patch -s -p1 -d drivers/usb/typec --dry-run -R -f -i \$f >/dev/null 2>&1 && continue
        patch -s -p1 -d drivers/usb/typec -f -i \$f >&2 || { echo \"error: \$(basename \$f) does not apply\" >&2; exit 1; }
        echo \"   applied: \$(basename \$f) (samsung-emuec)\" >&2
    done
    rm -f drivers/usb/typec/samsung-emuec.c.orig
    # same for samsung-galaxybook-ec (drivers/anatase/patches-galaxybook-ec;
    # 22 October: battery readings frozen on book4s)
    tar -xzf ~/src/.book4-build/gbec.tgz -C \$p
    for f in \$p/gbec/*.patch; do
        patch -s -p1 -d drivers/platform/arm64 --dry-run -R -f -i \$f >/dev/null 2>&1 && continue
        patch -s -p1 -d drivers/platform/arm64 -f -i \$f >&2 || { echo \"error: \$(basename \$f) does not apply\" >&2; exit 1; }
        echo \"   applied: \$(basename \$f) (samsung-galaxybook-ec)\" >&2
    done
    rm -f drivers/platform/arm64/samsung-galaxybook-ec.c.orig
    echo $sum > .book4-patches
else
    cd patchwork-sleep
    p=\$(mktemp -d); tar -xzf ~/src/.book4-build/patches.tgz -C \$p
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
grep -q 'galaxybook_battery_update' drivers/platform/arm64/samsung-galaxybook-ec.c || { echo 'error: samsung-galaxybook-ec has no battery refresh: run tools/kernel/update-sleep-galaxybook-ec.sh' >&2; exit 1; }
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
# The TEO idle governor next to menu (23 October): with menu, 83 % of
# cluster 0's CL5 entries end before CL5's minimum residency. Built in, it
# can be chosen at runtime (/sys/devices/system/cpu/cpuidle/current_governor);
# menu stays the default.
if ! grep -q '^CONFIG_CPU_IDLE_GOV_TEO=y' .config; then
    ./scripts/config --enable CPU_IDLE_GOV_TEO
    make -s LOCALVERSION=$lv olddefconfig
    echo '   config: CPU_IDLE_GOV_TEO' >&2
fi
grep -q '^CONFIG_CPU_IDLE_GOV_TEO=y' .config || { echo 'error: could not set CONFIG_CPU_IDLE_GOV_TEO' >&2; exit 1; }
# memlat (23 October, sleep-backport 0029-0036, Qualcomm's RFC v8): the
# CPUCP raises DDR/LLCC bandwidth when the CPUs wait on memory; without it
# memory stays at its lowest vote (SP11: 38 -> 67 GB/s). As modules, loaded
# by book4-el2-sleep.service (the vendor protocol does not autoload).
# Iris video codec at EL2 (25 October, sleep-backport 0040): the video
# clock controller (SM_VIDEOCC_8550 drives qcom,x1e80100-videocc) was never
# built; qcom-iris itself already is.
for o in QCOM_SCMI_GENERIC_EXT DEVFREQ_GOV_REMOTE SCMI_QCOM_MEMLAT_DEVFREQ SM_VIDEOCC_8550 VIDEO_QCOM_IRIS; do
    grep -q \"^CONFIG_\$o=[ym]\" .config && continue
    ./scripts/config --module \$o
    make -s LOCALVERSION=$lv olddefconfig
    grep -q \"^CONFIG_\$o=[ym]\" .config || { echo \"error: could not set CONFIG_\$o\" >&2; exit 1; }
    echo \"   config: \$o=m\" >&2
done
make -s -j\$(nproc) LOCALVERSION=$lv Image modules qcom/$dtbname >&2
out=~/src/sleep-out; rm -rf \$out; mkdir -p \$out
make -s LOCALVERSION=$lv INSTALL_MOD_PATH=\$out INSTALL_MOD_STRIP=1 DEPMOD=true modules_install >&2
m=\$(mktemp -d); tar -xzf ~/src/.book4-build/mods.tgz -C \$m
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
if [ -n "$staged" ]; then
    # Running $rel: stage the modules, build the initramfs from them.
    sudo rm -rf "$stage"; sudo mkdir -p "$stage/lib/modules"
    sudo cp -a "$src/lib/modules/$rel" "$stage/lib/modules/$rel"
    cp "$src/Image" "$src/$dtbname" "$work/"
    sudo umount "$h"; rmdir "$h"
    sudo depmod -b "$stage" $rel
    echo "   staged $stage/lib/modules/$rel: $(find "$stage/lib/modules/$rel" -name '*.ko*' | wc -l) modules (swapped in at the next boot)"
    sudo install -D -m 755 "$repo/userspace/boot/book4-modules-swap" /usr/local/lib/book4/modules-swap
    sudo install -m 644 "$repo/userspace/boot/book4-modules-swap.service" /etc/systemd/system/
    sudo systemctl daemon-reload; sudo systemctl enable -q book4-modules-swap.service
    sudo mkinitcpio -k $rel -r "$stage" -g "$work/initramfs.img" >/dev/null
else
    sudo rm -rf /usr/lib/modules/$rel.new
    sudo cp -a "$src/lib/modules/$rel" /usr/lib/modules/$rel.new
    cp "$src/Image" "$src/$dtbname" "$work/"
    sudo umount "$h"; rmdir "$h"
    sudo rm -rf /usr/lib/modules/$rel
    sudo mv /usr/lib/modules/$rel.new /usr/lib/modules/$rel
    sudo depmod $rel
    echo "   /usr/lib/modules/$rel: $(find /usr/lib/modules/$rel -name '*.ko*' | wc -l) modules"
    sudo mkinitcpio -k $rel -g "$work/initramfs.img" >/dev/null
fi
LIST=$(sudo lsinitcpio "$work/initramfs.img")   # captured: grep -q in a pipe trips pipefail
grep -qE '/ufs-qcom\.ko(\.[gx]z|\.zst)?$' <<<"$LIST" || { echo "error: ufs-qcom.ko missing from the initramfs" >&2; exit 1; }
# four speakers: tweeters, woofers named by side, no 0x43 repeater
dtc -q -@ -I dts -O dtb -o "$work/speakers.dtbo" "$repo/dts/src/x1e80100-book4-edge-14-speakers.dtso"
fdtoverlay -i "$work/$dtbname" -o "$work/speakers.dtb" "$work/speakers.dtbo"
dtc -q -I dtb -O dtb -p 8192 -o "$work/book4-sleep.dtb" "$work/speakers.dtb"   # padded for GRUB
[ "$(fdtget -ts "$work/book4-sleep.dtb" /soc@0/soundwire@6b10000/speaker@0,1 sound-name-prefix)" = TweeterLeft ] ||
    { echo "error: DTB has no tweeters" >&2; exit 1; }
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
[ -z "$staged" ] || echo "Then reboot whenever it suits you: the new modules are swapped in at boot."
