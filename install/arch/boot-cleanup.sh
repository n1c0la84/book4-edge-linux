#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Tidy the boot setup after the October experiments:
#   1. GRUB test entries (install/arch/test-entry.sh): keep only those named
#      on the command line (default: el2-sleep, the daily EL2 entry) and the
#      GRUB default line if it points at a kept entry;
#   2. files of ours on /boot (sda4) that no GRUB entry references any more:
#      our kernels (vmlinuz-*book4*), Arch initramfs images (*-arch.img) and
#      DTBs under /boot/dtb-test. The references are read from the ESP's
#      grub.cfg (written by Fedora's boot hook) and the kept test entries.
#      Anything else unreferenced (Fedora's own files) is only listed;
#   3. Arch module trees /usr/lib/modules/<release> whose /boot/vmlinuz-<release>
#      is gone (never the running kernel's).
# Shows everything it would remove and asks first. Never writes to the ESP
# or to Fedora.
#
# Run on Arch as your user:  bash install/arch/boot-cleanup.sh [KEEP ...]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
keep=("$@"); [ ${#keep[@]} -gt 0 ] || keep=(el2-sleep)
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
if findmnt -rn -S /dev/sda4 >/dev/null; then echo "error: /dev/sda4 (/boot) is mounted; unmount it first" >&2; exit 1; fi
sudo -v

echo "== 1. GRUB test entries (keeping: ${keep[*]})"
entries=$(bash "$here/test-entry.sh" list)
mapfile -t names < <(sed -n 's/^# test-entry: //p' <<<"$entries")
drop=()
for n in "${names[@]}"; do
    k=; for x in "${keep[@]}"; do [ "$n" = "$x" ] && k=1; done
    [ -n "$k" ] || drop+=("$n")
done
echo "   present: ${names[*]:-(none)}"
echo "   remove:  ${drop[*]:-(none)}"

b=$(mktemp -d); e=$(mktemp -d)
cleanup() { sudo umount "$b" "$e" 2>/dev/null || true; rmdir "$b" "$e"; }
trap cleanup EXIT
sudo mount -o ro /dev/sda4 "$b"
esp=$(findmnt -rno TARGET -S /dev/sda1 | head -1) || true
[ -n "$esp" ] || { sudo mount -o ro /dev/sda1 "$e"; esp=$e; }
# Paths under /boot that the main grub.cfg or a kept test entry uses.
refs=$( { sudo cat "$esp/EFI/fedora/grub.cfg"
          sudo cat "$b/book4-extra.cfg" 2>/dev/null | awk -v keep=" ${keep[*]} " '
              /^# test-entry: / { on = index(keep, " " $3 " ") > 0 }
              on { print }' ; } |
        grep -oE '\(\$bootdev\)/[^ ]+' | sed 's/^(\$bootdev)//' | sort -u)
# dtb-<kver>/ directories are the boot hook's own: kept with their kernel.
mapfile -t files < <(cd "$b" && sudo find . -maxdepth 1 -type f \( -name 'vmlinuz-*' -o -name 'initramfs-*' \) -printf '/%P\n';
                     cd "$b" && sudo find dtb-test -type f -name '*.dtb' -printf '/%p\n' 2>/dev/null)
unused=(); other=()
# Inputs of our scripts rather than of an entry: the sleep kernel's own DTB
# (install/el2/sleep-setup.sh makes the EL2 one from it).
protect="/dtb-test/book4-sleep.dtb"
for f in "${files[@]}"; do
    grep -qxF "$f" <<<"$refs" && continue
    grep -qxF "$f" <<<"$protect" && continue
    case "$f" in
        /vmlinuz-*book4*|/initramfs-*-arch.img|/dtb-test/*) unused+=("$f") ;;
        *) other+=("$f") ;;
    esac
done
echo "== 2. files of ours on /boot no entry uses"
printf '   %s\n' "${unused[@]:-(none)}"
[ ${#other[@]} -eq 0 ] || { echo "   not ours, kept (Fedora's):"; printf '      %s\n' "${other[@]}"; }

echo "== 3. Arch module trees without a kernel on /boot"
mods=()
for d in /usr/lib/modules/*/; do
    r=$(basename "$d")
    [ "$r" = "$(uname -r)" ] && continue
    gone=$(printf '%s\n' "${unused[@]:-}")   # here-strings: grep -q in a pipe trips pipefail
    [ -e "$b/vmlinuz-$r" ] && ! grep -qxF "/vmlinuz-$r" <<<"$gone" && continue
    mods+=("/usr/lib/modules/$r")
done
printf '   %s\n' "${mods[@]:-(none)}"

[ ${#drop[@]} -gt 0 ] || [ ${#unused[@]} -gt 0 ] || [ ${#mods[@]} -gt 0 ] || { echo "Nothing to do."; exit 0; }
read -rp "Remove all of the above? [y/N] " a
[ "$a" = y ] || [ "$a" = Y ] || { echo "Nothing removed."; exit 0; }

sudo umount "$b"
for n in "${drop[@]}"; do bash "$here/test-entry.sh" remove "$n"; done
sudo mount /dev/sda4 "$b"
for f in "${unused[@]}"; do sudo rm -f "$b$f" && echo "   removed /boot$f"; done
sudo find "$b/dtb-test" -type d -empty -delete 2>/dev/null || true
sync
for m in "${mods[@]}"; do sudo rm -rf --one-file-system "$m" && echo "   removed $m"; done
echo "Done. Remaining entries:"
sudo umount "$b"
bash "$here/test-entry.sh" list
sudo mount -o ro /dev/sda4 "$b"   # for the exit trap
