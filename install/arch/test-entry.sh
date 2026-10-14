#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Test boot entries for this system in the GRUB menu, managed from Arch.
# Each entry is a copy of the generated entry for the running subvolume (same
# kernel, DTB and initramfs) with changed kernel arguments or DTB. They live in
# /boot/book4-extra.cfg, which the boot hook's grub.cfg sources, so neither
# Fedora nor the ESP is touched. Never the default entry.
# Run as your user (sudo inside), with /boot (sda4) not mounted elsewhere.
#
#   bash install/arch/test-entry.sh add NAME [-ARG ...] [+ARG ...] [dtb=/PATH]
#        -ARG removes ARG (exact word, or KEY for KEY=...), +ARG appends it,
#        dtb=/dtb-test/x.dtb replaces the device tree (path under /boot)
#   bash install/arch/test-entry.sh list
#   bash install/arch/test-entry.sh remove NAME
#   bash install/arch/test-entry.sh clear
#
# Example: add synced -clk_ignore_unused -pd_ignore_unused +fw_devlink.sync_state=timeout
# NAME becomes part of the menu title: "<entry title> - test: NAME".
set -euo pipefail
BOOTDEV=/dev/sda4
ESPDEV=/dev/sda1
EXTRA=book4-extra.cfg
ESPCFG=EFI/fedora/grub.cfg

cmd=${1:-}; shift || true
case "$cmd" in add|remove) [ -n "${1:-}" ] || cmd=help ;; list|clear) ;; *) cmd=help ;; esac
if [ "$cmd" = help ]; then sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'; exit 1; fi

if [ -n "${BOOK4_TESTROOT:-}" ]; then   # self-test: plain directories, no mounts, no sudo
  SUDO=; esp=$BOOK4_TESTROOT/esp; boot=$BOOK4_TESTROOT/boot
else
  SUDO=sudo
  for d in $BOOTDEV $ESPDEV; do
    if findmnt -rn -S $d >/dev/null; then
      echo "error: $d is already mounted ($(findmnt -rn -o TARGET -S $d | tr '\n' ' ')); unmount it first (bash ~/mount-ro.sh off)." >&2
      exit 1
    fi
  done
  boot=$(mktemp -d); esp=$(mktemp -d)
  cleanup() { sudo umount "$boot" 2>/dev/null || true; sudo umount "$esp" 2>/dev/null || true; rmdir "$boot" "$esp"; }
  trap cleanup EXIT
  sudo mount -o ro $ESPDEV "$esp"
  if [ "$cmd" = list ]; then sudo mount -o ro $BOOTDEV "$boot"; else sudo mount $BOOTDEV "$boot"; fi
fi
file=$boot/$EXTRA

# Entries are blocks that start with "# test-entry: NAME" and end with "}".
drop() { [ -e "$file" ] && awk -v n="$1" '
  /^# test-entry: / { skip = ($3 == n) }
  !skip { print }
  skip && /^}/ { skip = 0 }' "$file" || true; }
write() { # stdin -> $file, atomically; an empty result removes the file
  local tmp; tmp=$(mktemp)
  cat > "$tmp"
  if grep -q '^menuentry' "$tmp"; then
    $SUDO install -m 644 "$tmp" "$file.new" && $SUDO mv "$file.new" "$file"
  else
    $SUDO rm -f "$file"
  fi
  rm -f "$tmp"; sync
}

case "$cmd" in
list)
  if [ -e "$file" ]; then grep -E '^(# test-entry|menuentry|    linux|    devicetree)' "$file"; else echo "(no test entries)"; fi
  exit 0 ;;
clear)
  $SUDO rm -f "$file"; sync; echo "removed all test entries"; exit 0 ;;
remove)
  drop "$1" | write; echo "removed test entry '$1'"; exit 0 ;;
esac

name=$1; shift
[[ $name =~ ^[A-Za-z0-9._+-]+$ ]] || { echo "error: NAME may only use letters, digits and . _ + -" >&2; exit 1; }

# The generated entry for the subvolume we are running from.
subvol=$(findmnt -rn -o FSROOT /); subvol=${subvol#/}
block=$(awk -v sv="rootflags=subvol=$subvol" '
  /^menuentry / { buf = $0 "\n"; inside = 1; next }
  inside { buf = buf $0 "\n" }
  inside && /^}/ { inside = 0; if (index(buf, sv) && !found) { printf "%s", buf; found = 1 } }' "$esp/$ESPCFG")
[ -n "$block" ] || { echo "error: no entry with rootflags=subvol=$subvol in $ESPCFG" >&2; exit 1; }

title=$(sed -n '1s/^menuentry "\(.*\)" {$/\1/p' <<<"$block")
dt=$(sed -n 's/^[[:space:]]*devicetree[[:space:]]\+//p' <<<"$block")
linux=$(sed -n 's/^[[:space:]]*linux[[:space:]]\+//p' <<<"$block")
initrd=$(sed -n 's/^[[:space:]]*initrd[[:space:]]\+//p' <<<"$block")
[ -n "$title" ] && [ -n "$dt" ] && [ -n "$linux" ] && [ -n "$initrd" ] || { echo "error: could not parse the entry:" >&2; echo "$block" >&2; exit 1; }

read -ra words <<<"$linux"   # words[0] = kernel image, the rest = arguments
args=("${words[@]:1}")
for a in "$@"; do
  case "$a" in
    -*) k=${a#-}; new=()
        for w in "${args[@]}"; do [ "$w" = "$k" ] || [ "${w%%=*}" = "$k" ] || new+=("$w"); done
        [ ${#new[@]} -lt ${#args[@]} ] || { echo "error: '$k' is not in the command line" >&2; exit 1; }
        args=("${new[@]}") ;;
    +*) args+=("${a#+}") ;;
    dtb=/*) p=${a#dtb=}
        [ -e "$boot$p" ] || { echo "error: $p does not exist under /boot" >&2; exit 1; }
        dt="(\$bootdev)$p" ;;
    *) echo "error: '$a': use -ARG, +ARG or dtb=/PATH" >&2; exit 1 ;;
  esac
done

{ drop "$name"
  [ -e "$file" ] || echo "# Test entries for the second OS, sourced by the boot hook's grub.cfg; written by install/arch/test-entry.sh."
  cat <<EOF

# test-entry: $name
menuentry "$title - test: $name" {
    devicetree $dt
    linux  ${words[0]} ${args[*]}
    initrd $initrd
}
EOF
} | write
echo "Added to /boot/$EXTRA:"
awk -v n="$name" '$0 == "# test-entry: " n { p = 1 } p { print } p && /^}/ { exit }' "$file"
