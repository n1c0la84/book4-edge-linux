#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Part C (docs/plan-arch-boot.md): retire Fedora without deleting it. Copies
# everything worth keeping from Fedora's home into Arch, so that deleting
# Fedora later loses nothing. Fedora's subvolumes, /boot files and ESP
# files are only read. Run as your user on Arch:
#
#   bash install/arch/fedora-retire.sh archive    copy into ~/fedora-archive/ (again: updates it)
#   bash install/arch/fedora-retire.sh status     what is archived, what Fedora still holds
#
# What goes where:
#   ~/fedora-archive/home/   Fedora's home without the big rebuildable parts
#       (kernel trees, build outputs, .cache, Chrome's 3.5 GB profile) as
#       reflinked copies: no extra space while Fedora still exists
#   kernel trees (src/patchwork, src/patchwork-sleep, src/linux-73): every
#       local branch fetched into ~/src/linux-book4 as refs/fedora/<tree>/*
#       (a shallow tree's whole .git reflinked to ~/fedora-archive/kernel/<tree>.git
#       instead: fetching from it would make linux-book4 shallow),
#       uncommitted changes as ~/fedora-archive/kernel/<tree>.dirty.patch,
#       untracked files as <tree>.untracked.tar, the .config as <tree>.config
#   ~/fedora-archive/MANIFEST.txt   what was copied, with sizes and refs
#
# BOOK4_FEDORA_CHROME=1 also copies .config/google-chrome (bookmarks,
# passwords and history of Fedora's Chrome profile).
set -euo pipefail
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
DEV_ROOT=/dev/disk/by-uuid/4d74e1d5-7bca-48bf-a6e0-1362fd77882e   # btrfs (sda5)
A=$HOME/fedora-archive
TREES=(patchwork patchwork-sleep linux-73)
KREPO=$HOME/src/linux-book4
cmd=${1:-}
case "$cmd" in archive|status) ;; *) sed -n '3,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 1 ;; esac

sudo -v
m=$(mktemp -d); sudo mount -o ro,subvol=home "$DEV_ROOT" "$m"
trap 'sudo umount "$m"; rmdir "$m"' EXIT
F=$m/$USER
[ -d "$F" ] || { echo "error: no $USER in Fedora's home subvolume" >&2; exit 1; }

if [ "$cmd" = status ]; then
    echo "== Fedora's home: $(du -xsh "$F" 2>/dev/null | cut -f1)"
    [ -e "$A/MANIFEST.txt" ] && { echo "== archive ($A):"; sed 's/^/   /' "$A/MANIFEST.txt"; } || echo "== no archive yet"
    exit 0
fi

mkdir -p "$A/home" "$A/kernel"
echo "== 1. Fedora's home -> $A/home (reflinked, without the rebuildable parts)"
ex=(--exclude=/.cache --exclude=/src/linux-73 --exclude=/src/patchwork --exclude=/src/patchwork-sleep
    --exclude=/src/out-73 --exclude=/src/sleep-out --exclude=/rpmbuild/BUILD --exclude=/.local/share/Trash)
[ "${BOOK4_FEDORA_CHROME:-0}" = 1 ] || ex+=(--exclude=/.config/google-chrome)
# rsync for the selection, then each file reflinked over by cp (same btrfs).
( cd "$F" && rsync -a --no-whole-file --inplace "${ex[@]}" --dry-run --out-format='%n' ./ "$A/home/" ) > "$A/.todo"
( cd "$F" && while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -d "$p" ] && [ ! -L "$p" ]; then mkdir -p "$A/home/$p"
    else mkdir -p "$A/home/$(dirname "$p")"; cp -a --reflink=always "$p" "$A/home/$p" 2>/dev/null || cp -a "$p" "$A/home/$p"; fi
  done < "$A/.todo" )
rm -f "$A/.todo"
echo "   $(du -sh "$A/home" | cut -f1) apparent, $(find "$A/home" -type f | wc -l) files"

echo "== 2. kernel trees -> refs/fedora/<tree>/* in $KREPO, plus dirty patches"
[ -d "$KREPO/.git" ] || { echo "error: no $KREPO" >&2; exit 1; }
for t in "${TREES[@]}"; do
    r=$F/src/$t; [ -d "$r/.git" ] || { echo "   $t: no git tree, skipped"; continue; }
    g() { git -c safe.directory='*' -C "$r" --no-optional-locks "$@"; }
    if [ "$(g rev-parse --is-shallow-repository)" = true ]; then
        rm -rf "$A/kernel/$t.git"; cp -a --reflink=auto "$r/.git" "$A/kernel/$t.git"
        git -C "$A/kernel/$t.git" config core.bare true
    else
        git -C "$KREPO" fetch -q --no-tags "$r" "+refs/heads/*:refs/fedora/$t/*"
    fi
    g diff HEAD > "$A/kernel/$t.dirty.patch"
    [ -s "$A/kernel/$t.dirty.patch" ] || rm -f "$A/kernel/$t.dirty.patch"
    u=$(g ls-files --others --exclude-standard)
    if [ -n "$u" ]; then (cd "$r" && tar -cf "$A/kernel/$t.untracked.tar" $u); else rm -f "$A/kernel/$t.untracked.tar"; fi
    [ ! -e "$r/.config" ] || cp "$r/.config" "$A/kernel/$t.config"
    echo "$t $(g rev-parse --abbrev-ref HEAD) $(g rev-parse HEAD)" > "$A/kernel/$t.head"
    echo "   $t: $( [ -d "$A/kernel/$t.git" ] && echo "$t.git copied" || echo "$(git -C "$KREPO" for-each-ref "refs/fedora/$t/" | wc -l) branches fetched"); HEAD $(cut -d' ' -f2 "$A/kernel/$t.head")$( [ -e "$A/kernel/$t.dirty.patch" ] && echo ", dirty patch $(grep -c '^diff --git' "$A/kernel/$t.dirty.patch") files")"
done

echo "== 3. check: every local commit of the trees is reachable from refs/fedora"
bad=0
for t in "${TREES[@]}"; do
    r=$F/src/$t; [ -d "$r/.git" ] || continue
    for h in $(git -c safe.directory='*' -C "$r" for-each-ref --format='%(objectname)' refs/heads); do
        dst=$KREPO; [ ! -d "$A/kernel/$t.git" ] || dst=$A/kernel/$t.git
        git -C "$dst" cat-file -e "$h^{commit}" 2>/dev/null || { echo "   MISSING $t $h"; bad=1; }
    done
done
[ $bad = 0 ] && echo "   all branch heads present" || { echo "error: some branch heads are missing" >&2; exit 1; }

{ echo "Fedora archive, $(date -Iseconds) (install/arch/fedora-retire.sh)"
  echo "home/: $(du -sh "$A/home" | cut -f1) apparent, $(find "$A/home" -type f | wc -l) files; excluded: ${ex[*]}"
  for t in "${TREES[@]}"; do
      [ -e "$A/kernel/$t.head" ] || continue
      if [ -d "$A/kernel/$t.git" ]; then
          echo "kernel $t: HEAD $(cut -d' ' -f2- "$A/kernel/$t.head"); repository $A/kernel/$t.git, branches:"
          git -C "$A/kernel/$t.git" for-each-ref --format='    %(refname:lstrip=2) %(objectname:short) %(subject)' refs/heads/
      else
          echo "kernel $t: HEAD $(cut -d' ' -f2- "$A/kernel/$t.head"); branches in $KREPO refs/fedora/$t/:"
          git -C "$KREPO" for-each-ref --format='    %(refname:lstrip=3) %(objectname:short) %(subject)' "refs/fedora/$t/"
      fi
      ls -d "$A/kernel/$t".* 2>/dev/null | sed 's/^/    file /'
  done
} > "$A/MANIFEST.txt"
echo; echo "Done: $A/MANIFEST.txt. Fedora itself is unchanged."
