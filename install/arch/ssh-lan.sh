#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# SSH into this Arch from the home network only, with password login.
#  - ufw: allow TCP 22 from the subnet of the current default route only
#    (everything else stays dropped, as Omarchy set it up)
#  - sshd drop-in: passwords on, root never, only your user, 3 tries per
#    connection (Omarchy's faillock still locks the account after 10 failures)
# Run as your own user, connected to the home network:
#   bash install/arch/ssh-lan.sh      (sudo is used inside)
set -euo pipefail
if (( EUID == 0 )); then
  echo "Run as your user, not as root." >&2
  exit 1
fi
U=$(id -un)
dev=$(ip -4 route show default | awk '{print $5; exit}')
[[ -n $dev ]] || { echo "No default route: connect to the home network first." >&2; exit 1; }
LAN=$(ip -4 route show dev "$dev" proto kernel scope link | awk '{print $1; exit}')
[[ $LAN =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]] ||
  { echo "Subnet '$LAN' on $dev is not a private home network; stopping." >&2; exit 1; }
echo "home network: $LAN on $dev"

sudo -v
sudo install -D -m 644 /dev/stdin /etc/ssh/sshd_config.d/10-book4.conf <<EOF
# book4: password login from the home network (the firewall limits port 22
# to the local subnet); never root, only $U.
PasswordAuthentication yes
PermitRootLogin no
AllowUsers $U
MaxAuthTries 3
EOF
sudo sshd -t
sudo systemctl enable --now sshd.service >/dev/null
sudo systemctl reload sshd.service

sudo ufw allow from "$LAN" to any port 22 proto tcp comment 'ssh from home network'
sudo ufw status verbose | sed -n '1,4p;/22\/tcp/p'
echo
echo "From another computer on this network:  ssh $U@$(ip -4 -o addr show dev "$dev" | awk '{split($4,a,"/"); print a[1]; exit}')"
echo "or, with mDNS:                           ssh $U@$(hostname).local"
