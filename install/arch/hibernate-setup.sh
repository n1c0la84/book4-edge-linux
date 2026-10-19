#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Hibernation for Arch on this machine (docs/power.md: s2idle never reaches
# SoC deep sleep, so a night of suspend empties the battery).
#
#   1. a 16 GiB swap file in its own btrfs subvolume (/swap), priority below
#      zram, so it is only used for the hibernation image;
#   2. a systemd service that stops the ADSP/CDSP before hibernating and
#      starts them after resume: their firmware is gone after power-off and
#      qcom_q6v5_pas cannot restore it (battery, charging, USB-C and audio go
#      through the ADSP). It runs before systemd-hibernate.service, i.e.
#      before systemd freezes the user session: stopping the ADSP removes the
#      sound card, which waits for PipeWire to close it, and a frozen
#      PipeWire never does (a system-sleep hook deadlocked that way, 19 Oct).
#
# Nothing else is needed: the EFI variable driver (qseecom/uefisecapp) is
# built in, so systemd records the image location in the HibernateLocation
# EFI variable, and Arch's initramfs (mkinitcpio "systemd" hook) resumes from
# it. No resume= on the kernel command line, which Fedora shares.
#
# Then test by hand: systemctl hibernate, power on, let GRUB boot Arch.
# Never boot Fedora while Arch is hibernated: both mount the same btrfs
# filesystem (sda5), and resuming over Fedora's changes can corrupt it.
#
# Run as your user on Arch:  bash install/arch/hibernate-setup.sh [undo]
set -euo pipefail
undo=${1:-}
size=16g
sub=/swap
file=$sub/swapfile
fstab="$file none swap defaults,pri=0 0 0"
oldhook=/usr/lib/systemd/system-sleep/book4-dsp   # 19 Oct version, deadlocks
helper=/usr/local/lib/book4/dsp-ctl
unit=/etc/systemd/system/book4-dsp-hibernate.service

[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }
[ "$(findmnt -no FSTYPE /)" = btrfs ] || { echo "/ is not btrfs." >&2; exit 1; }
grep -qw disk /sys/power/state || { echo "The kernel does not offer hibernation (no 'disk' in /sys/power/state)." >&2; exit 1; }
sudo -v

if [ "$undo" = undo ]; then
    sudo swapoff "$file" 2>/dev/null || true
    sudo sed -i "\|^$file |d" /etc/fstab
    sudo systemctl disable book4-dsp-hibernate.service 2>/dev/null || true
    sudo rm -f "$file" "$oldhook" "$helper" "$unit"
    sudo systemctl daemon-reload
    [ -d "$sub" ] && sudo btrfs subvolume delete "$sub"
    echo "Hibernation setup removed."
    swapon --show
    exit 0
fi

echo "== 1. swap file $file ($size)"
if [ ! -e "$file" ]; then
    [ -d "$sub" ] || sudo btrfs subvolume create "$sub"
    sudo btrfs filesystem mkswapfile --size "$size" "$file"
fi
grep -q "^$file " /etc/fstab || echo "$fstab" | sudo tee -a /etc/fstab >/dev/null
swapon --show=NAME --noheadings | grep -qx "$file" || sudo swapon "$file"
swapon --show

echo "== 2. DSP stop/start around hibernation ($unit)"
sudo rm -f "$oldhook"
sudo mkdir -p "$(dirname "$helper")"
sudo tee "$helper" >/dev/null <<'EOF'
#!/bin/sh
# Book4 (install/arch/hibernate-setup.sh): stop|start the remoteprocs (ADSP,
# CDSP). Their firmware does not survive power-off and qcom_q6v5_pas cannot
# restore it, so they are stopped before hibernating and started after resume.
for r in /sys/class/remoteproc/remoteproc*; do
    [ -e "$r/state" ] || continue
    case "$1" in
    stop)  [ "$(cat "$r/state")" = running ] && echo stop > "$r/state" ;;
    start) [ "$(cat "$r/state")" = offline ] && echo start > "$r/state" ;;
    esac
done
exit 0
EOF
sudo chmod 755 "$helper"
sudo tee "$unit" >/dev/null <<EOF
# Book4 (install/arch/hibernate-setup.sh)
[Unit]
Description=Book4: stop the DSPs before hibernation, start them after resume
Before=systemd-hibernate.service
StopWhenUnneeded=yes

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$helper stop
ExecStop=$helper start

[Install]
WantedBy=hibernate.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable book4-dsp-hibernate.service
systemctl list-dependencies --plain hibernate.target | grep -E 'book4|systemd-hibernate' | sed 's/^/   /' || true

echo "== 3. checks"
k=$(uname -r)
img=initramfs-$k-arch.img
boot=$(findmnt -rn -o TARGET -S /dev/sda4 | head -1 || true)
tmp=
if [ -z "$boot" ]; then
    tmp=$(mktemp -d); sudo mount -o ro /dev/sda4 "$tmp"; boot=$tmp
fi
if sudo lsinitcpio "$boot/$img" 2>/dev/null | grep -q systemd-hibernate-resume; then
    echo "   $img: has systemd-hibernate-resume"
else
    echo "   WARNING: $img has no systemd-hibernate-resume; do not hibernate (see install/arch/sync-kernel.sh)"
fi
[ -n "$tmp" ] && { sudo umount "$tmp"; rmdir "$tmp"; }
echo "   logind CanHibernate: $(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate 2>/dev/null || echo '?')"
echo
echo "Done. Test: save your work, then  systemctl hibernate"
echo "It powers off; press power, let GRUB boot Arch (NOT Fedora). After resume check:"
echo "battery %, charging, sound, Wi-Fi, Bluetooth, USB; then: bash install/arch/hibernate-lid.sh"
