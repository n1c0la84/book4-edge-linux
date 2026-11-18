#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Install a linux-book4* package built by packages/linux-book4/PKGBUILD
# (docs/plan-arch-boot.md, part A) and make it bootable as today: kernel,
# initramfs and the EL2 DTB on /boot (sda4, Fedora's /boot until part B),
# plus the GRUB test entry "... - test: <name>". Run as your user on Arch.
#
#   bash tools/kernel/install-book4-kernel.sh book4p     install the newest linux-book4p package, entry "book4p"
#   bash tools/kernel/install-book4-kernel.sh book4p remove   entry, /boot files and the package gone
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); repo=$(cd "$here/../.." && pwd)
name=${1:?suffix name, e.g. book4p}
pkg=linux-$name; pkgdir=$repo/packages/linux-book4
dtbname=x1e80100-samsung-galaxy-book4-edge-14.dtb
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
if findmnt -rn -S /dev/sda4 >/dev/null; then echo "error: /dev/sda4 (/boot) is mounted; unmount it first" >&2; exit 1; fi

if [ "${2:-}" = remove ]; then
    rel=$(pacman -Ql "$pkg" 2>/dev/null | awk -F/ '$4=="modules" && $5!="" {print $5; exit}')
    [ -n "$rel" ] || { echo "$pkg is not installed" >&2; exit 1; }
    [ "$(uname -r)" != "$rel" ] || { echo "error: $rel is running" >&2; exit 1; }
    sudo -v
    bash "$repo/install/arch/test-entry.sh" remove "$name" || true
    b=$(mktemp -d); sudo mount /dev/sda4 "$b"
    sudo rm -f "$b/vmlinuz-$rel" "$b/initramfs-$rel-arch.img" "$b/dtb-test/$name.dtb" "$b/dtb-test/$name-el2.dtb"
    sync; sudo umount "$b"; rmdir "$b"
    sudo pacman -R --noconfirm "$pkg" "$pkg-headers" 2>/dev/null || sudo pacman -R --noconfirm "$pkg"
    echo "removed $pkg ($rel)"; exit 0
fi

files=$(ls -t "$pkgdir"/$pkg-[0-9]*.pkg.tar.* "$pkgdir"/$pkg-headers-[0-9]*.pkg.tar.* 2>/dev/null | grep -v '\.sig$' | head -2)
[ -n "$files" ] || { echo "error: no $pkg package in $pkgdir; build it first (makepkg)" >&2; exit 1; }
echo "== 1. pacman -U"; echo "$files" | sed 's/^/   /'
sudo pacman -U --noconfirm $files
rel=$(pacman -Ql "$pkg" | awk -F/ '$4=="modules" && $5!="" {print $5; exit}')
[ "$(uname -r)" != "$rel" ] || { echo "error: $rel is running; boot another kernel to reinstall it" >&2; exit 1; }
mod=/usr/lib/modules/$rel
[ -e "$mod/vmlinuz" ] && [ -e "$mod/dtb/qcom/$dtbname" ] || { echo "error: $mod lacks vmlinuz or the DTB" >&2; exit 1; }
sudo depmod "$rel"
echo "   $rel: $(find "$mod" -name '*.ko*' | wc -l) modules, extra: $(ls "$mod/extra" | tr '\n' ' ')"

echo "== 2. initramfs and /boot"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
sudo mkinitcpio -k "$rel" -g "$work/initramfs.img" >/dev/null 2>&1 || true
sudo chmod 644 "$work/initramfs.img"
lsinitcpio "$work/initramfs.img" | grep -qE '/ufs-qcom\.ko' || { echo "error: ufs-qcom.ko missing from the initramfs" >&2; exit 1; }
b=$(mktemp -d); sudo mount /dev/sda4 "$b"
sudo install -m 644 "$mod/vmlinuz" "$b/vmlinuz-$rel"
sudo install -m 644 "$work/initramfs.img" "$b/initramfs-$rel-arch.img"
sudo install -m 644 "$mod/dtb/qcom/$dtbname" "$b/dtb-test/$name.dtb"
sync; df -h "$b" | tail -1; sudo umount "$b"; rmdir "$b"

echo "== 3. GRUB entry '$name'"
bash "$repo/install/arch/test-entry.sh" remove "$name" >/dev/null 2>&1 || true
bash "$repo/install/el2/el2-dtb.sh" "/dtb-test/$name.dtb" "$name" -clk_ignore_unused -pd_ignore_unused \
    "kernel=/vmlinuz-$rel" "initrd=/initramfs-$rel-arch.img"
echo; echo "Installed $rel as '... - test: $name'. Reboot and pick it in GRUB."
