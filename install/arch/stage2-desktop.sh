#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Arch stage 2 (after stage1-base.sh): Hyprland + Quickshell desktop from
# Arch Linux ARM, SDDM login, audio with our UCM profile, the Bluetooth
# address fix, camera through PipeWire, keyboard layout, and a starter
# Hyprland (Lua) config. No bootloader changes. Done from Fedora in a
# container. Run as your user on Fedora.
set -euo pipefail
TOP=/mnt/btrfs-top
R=$TOP/arch
REPO=$(cd "$(dirname "$0")/../.." && pwd)
U=${ARCH_USER:-$USER}
KEYMAP=${ARCH_KEYMAP:-it}        # console keymap and XKB layout
SCALE=${ARCH_SCALE:-2.0}
ns() { sudo systemd-nspawn -q -D "$R" --resolv-conf=replace-uplink "$@"; }

sudo -v
sudo mkdir -p $TOP
mountpoint -q $TOP || sudo mount -o subvolid=5 /dev/sda5 $TOP

echo "== keyboard layout"
echo "KEYMAP=$KEYMAP" | sudo tee "$R/etc/vconsole.conf" >/dev/null
sudo install -D -m 644 /dev/stdin "$R/etc/X11/xorg.conf.d/00-keyboard.conf" <<EOF
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "$KEYMAP"
EndSection
EOF

echo "== packages"
ns pacman -Syu --noconfirm --needed linux-firmware-qcom \
    hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hypridle hyprlock \
    hyprpaper hyprpolkitagent quickshell uwsm sddm \
    pipewire pipewire-pulse pipewire-alsa pipewire-libcamera wireplumber alsa-utils \
    mesa vulkan-freedreno foot alacritty chromium \
    ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji \
    polkit gnome-keyring brightnessctl playerctl wl-clipboard grim slurp mako swayosd \
    network-manager-applet nm-connection-editor blueman pavucontrol xdg-user-dirs \
    qt6-wayland qt5-wayland fuzzel wofi libcamera-tools

echo "== audio: topology alias is already in firmware/updates; UCM profile"
sudo install -m 644 $REPO/userspace/audio/ucm2/*.conf "$R/usr/share/alsa/ucm2/Qualcomm/x1e80100/"
dmi() { tr -d ' ,\n' < /sys/devices/virtual/dmi/id/$1 | tr - _; }
LONG="$(dmi sys_vendor)-$(dmi product_name)-$(dmi product_version)-$(dmi board_name)"
sudo install -d "$R/usr/share/alsa/ucm2/conf.d/x1e80100"
sudo ln -sfn ../../Qualcomm/x1e80100/Samsung-GalaxyBook4Edge.conf \
    "$R/usr/share/alsa/ucm2/conf.d/x1e80100/$LONG.conf"

echo "== Bluetooth public address (same as on Fedora)"
# From Fedora's /etc/book4/bt-address (see userspace/bluetooth)
ADDR=$(cat /etc/book4/bt-address 2>/dev/null || sed -n 's/^ADDR=//p' /usr/local/sbin/book4-bt-addr)
sudo install -d "$R/etc/book4"
echo "$ADDR" | sudo tee "$R/etc/book4/bt-address" >/dev/null
sudo install -m 755 $REPO/userspace/bluetooth/book4-bt-addr "$R/usr/local/sbin/book4-bt-addr"
sudo install -m 644 $REPO/userspace/bluetooth/book4-bt-addr.service "$R/etc/systemd/system/book4-bt-addr.service"

echo "== services"
ns systemctl enable sddm book4-bt-addr.service

echo "== Hyprland 0.56 starter config (Lua)"
ns -u "$U" --setenv=SCALE=$SCALE --setenv=KEYMAP=$KEYMAP /bin/bash -euc '
C=~/.config/hypr/hyprland.lua
mkdir -p ~/.config/hypr
if [ ! -e $C ]; then
    cp /usr/share/hypr/hyprland.lua $C
    sed -i -e "0,/scale    = \"auto\"/s//scale    = $SCALE/" \
           -e "s/^local terminal    = \"kitty\"/local terminal    = \"foot\"/" \
           -e "s/^local menu        = \"hyprlauncher\"/local menu        = \"fuzzel\"/" \
           -e "s/kb_layout  = \"us\"/kb_layout  = \"$KEYMAP\"/" \
           -e "s/natural_scroll = false/natural_scroll = true/" $C
    cat >> $C <<EOF

-- Book4 starter additions (Omarchy will replace this config later)
hl.on("hyprland.start", function()
    hl.exec_cmd("mako")
    hl.exec_cmd("nm-applet")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
end)
EOF
fi
grep -nE "scale    =|^local terminal|^local menu|kb_layout|natural_scroll" $C
xdg-user-dirs-update || true
'
sudo umount $TOP
echo "Done. Reboot into Arch: SDDM, then the Hyprland session."
