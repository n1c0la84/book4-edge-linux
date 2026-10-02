#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copy the last Arch boot's logs (login, Hyprland, SDDM) to ~/arch-logs.txt
# so Claude can read them from Fedora. Run as your user.
set -u
sudo -v
TOP=/mnt/btrfs-top
sudo mkdir -p $TOP
mountpoint -q $TOP || sudo mount -o subvolid=5 /dev/sda5 $TOP
J=$TOP/arch/var/log/journal
H=$TOP/arch/home/${ARCH_USER:-$USER}
{
echo "== boots"; sudo journalctl -D $J --list-boots --no-pager | tail -3
B=$(sudo journalctl -D $J --list-boots --no-pager | awk 'END{print $2}')
echo "== errors and session messages, last Arch boot $B"
sudo journalctl -D $J -b $B --no-pager -o short-monotonic 2>/dev/null | grep -iE 'sddm|hyprland|uwsm|session|pam|login|wayland|EGL|drm|msm|segfault|core dump|failed|error' | grep -viE 'audit' | tail -150
echo "== SDDM log"; sudo tail -50 $TOP/arch/var/log/sddm.log 2>/dev/null
echo "== Hyprland logs"; sudo find $H/.local/share/hyprland $H/.cache/hyprland /run/user 2>/dev/null -name '*.log' | head
for f in $(sudo find $H -path '*hypr*' -name '*.log' 2>/dev/null | head -3); do echo "-- $f"; sudo tail -60 "$f"; done
echo "== uwsm / xsession errors"; sudo tail -40 $H/.local/share/sddm/wayland-session.log 2>/dev/null; sudo tail -40 $H/.local/share/sddm/xorg-session.log 2>/dev/null
echo "== sessions offered"; ls $TOP/arch/usr/share/wayland-sessions/
} > ~/arch-logs.txt 2>&1
sudo umount $TOP
echo "saved ~/arch-logs.txt ($(wc -l < ~/arch-logs.txt) lines)"
