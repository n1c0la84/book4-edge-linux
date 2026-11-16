#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Boot Omarchy's own kernel (linux-omarchy, edge channel) on this system from
# a GRUB test entry, at EL1 as a stock install would: the boot test birkskyum
# asked for in omarchy#15860, without installing Omarchy's image. Nothing of
# the daily setup is replaced: the kernel gets its own module tree, initramfs,
# DTB (Omarchy's 14" tree) and entry "... - test: omarchy-edge".
#
#   bash tools/experiments/omarchy-kernel-test.sh            install the entry
#   bash tools/experiments/omarchy-kernel-test.sh report     on that boot: summary + redacted kernel log
#   bash tools/experiments/omarchy-kernel-test.sh undo       remove entry, files and modules
#
# What it does (install):
#   1. reads the current linux-omarchy and linux-omarchy-dtbs versions from
#      pkgs.omarchy.org/edge/aarch64, downloads both, checks the signatures
#      against the Omarchy key already in pacman's keyring;
#   2. unpacks only /usr/lib/modules/<release> (not a pacman install: no
#      hooks, no Limine, nothing else touched), depmod;
#   3. builds an initramfs for it. linux-omarchy has the Qualcomm platform
#      drivers as modules, so they are all named (clock, pinctrl,
#      interconnect, regulators, PHYs, UFS), plus Omarchy's own list;
#   4. copies kernel, initramfs and Omarchy's DTB to /boot and adds the entry
#      with a stock-like command line: no mem_sleep_default (so deep is the
#      default, as on a stock install), no pcie_port_pm=force, and
#      qcom_aoss.prevent_aoss_sleep=1 (linux-omarchy 7.3-64+: AOSD off; with
#      AOSD on, a deep suspend lost UFS here on 15 November).
#
# To boot it: sudo efibootmgr -n 0001 && systemctl reboot, then pick
# "... - test: omarchy-edge" (EL1; the slbounce entry would boot it at EL2).
# Expect: no battery reading or charging control (no Samsung EC driver in
# that kernel), qcom_adsp_pwr_lmts stays blacklisted by our modprobe.d (it
# crashes this ADSP; a stock install would load it). If it hangs: hold power.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
URL=${OMARCHY_PKGS_URL:-https://pkgs.omarchy.org/edge/aarch64}
cache=${XDG_CACHE_HOME:-$HOME/.cache}/book4/omarchy-kernel
name=omarchy-edge
dtb=x1e80100-samsung-galaxy-book4-edge-14.dtb
relfile=$cache/release
[ -e /etc/arch-release ] || { echo "Run this on Arch." >&2; exit 1; }

report() {
    local out=$HOME/omarchy-edge-report rel
    rel=$(uname -r)
    case $rel in *omarchy*) ;; *) echo "error: this is not the linux-omarchy boot (running $rel)" >&2; exit 1 ;; esac
    mkdir -p "$out"; sudo -v
    {
        echo "kernel: $rel"
        echo "cmdline: $(sed -E 's/root=UUID=[^ ]+/root=UUID=<redacted>/' /proc/cmdline)"
        echo "EL: $(journalctl -k -b -o cat | grep -m1 'started at EL' || echo unknown)"
        echo "compatible: $(tr '\0' ' ' < /proc/device-tree/compatible)"
        echo "prevent_aoss_sleep: $(cat /sys/module/qcom_aoss/parameters/prevent_aoss_sleep 2>/dev/null || echo 'no such parameter')"
        echo "mem_sleep: $(cat /sys/power/mem_sleep)"
        echo "providers not synced: $(grep -L 1 $(find /sys/devices -name state_synced) 2>/dev/null | tr '\n' ' ')"
        echo "DSPs: $(for r in /sys/class/remoteproc/remoteproc*; do printf '%s=%s ' "$(cat $r/name)" "$(cat $r/state)"; done)"
        echo "sound cards: $(grep -c '^ *[0-9]' /proc/asound/cards 2>/dev/null || echo 0)"
        echo "battery: $(ls /sys/class/power_supply 2>/dev/null | tr '\n' ' ')"
        echo "wifi: $(ip -br link show wlan0 2>/dev/null | awk '{print $2}')"
        echo "failed units: $(systemctl --failed --no-legend | awk '{print $2}' | tr '\n' ' ')"
        echo "== sleep counters"
        for s in apss aosd cxsd ddr; do printf '%s: %s\n' $s "$(sudo cat /sys/kernel/debug/qcom_stats/$s 2>/dev/null | tr '\n' ' ')"; done
        echo "== system power domain"
        sudo cat /sys/kernel/debug/pm_genpd/power-domain-system/idle_states 2>/dev/null
        echo "== sleeps on this boot"
        journalctl -t book4-sleep -b --no-pager -o cat | tail -5
        echo "== suspend/resume and storage lines"
        journalctl -k -b -o cat | grep -E 'PM: suspend|ufs|UFS|phy init|BTRFS (warn|err)|adsp|cdsp|remoteproc' | tail -40
    } > "$out/summary.txt" 2>&1
    # kernel log with addresses and names taken out
    journalctl -k -b -o short-monotonic --no-pager |
        sed -E -e 's/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/<mac>/g' \
               -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/<ip>/g' \
               -e 's/root=UUID=[^ ]+/root=UUID=<redacted>/g' \
               -e 's/(SerialNumber: ).*/\1<redacted>/' \
               -e "s/$(hostname)/<host>/g" \
               -e 's/(SSID[=: ]+)[^ ,]+/\1<redacted>/g' > "$out/kernel.log"
    echo "Written: $out/summary.txt and $out/kernel.log"
    echo "Check before posting: grep -nE '([0-9a-f]{2}:){5}|SSID|Serial' $out/kernel.log"
    cat "$out/summary.txt"
}

undo() {
    local rel; rel=$(cat "$relfile" 2>/dev/null || true)
    [ "$(uname -r)" != "$rel" ] || { echo "error: this kernel is running; boot the daily entry first" >&2; exit 1; }
    bash "$repo/install/arch/test-entry.sh" remove $name || true
    if [ -n "$rel" ]; then
        b=$(mktemp -d); sudo mount /dev/sda4 "$b"
        sudo rm -f "$b/vmlinuz-$rel" "$b/initramfs-$rel-arch.img" "$b/dtb-test/omarchy-edge-14.dtb"
        sync; sudo umount "$b"; rmdir "$b"
        case $rel in *omarchy*) sudo rm -rf --one-file-system "/usr/lib/modules/$rel" ;; esac
        echo "removed kernel $rel, its initramfs, DTB and modules"
    fi
}

case "${1:-install}" in report) report; exit 0 ;; undo) undo; exit 0 ;; install) ;; *) sed -n '3,12p' "$0"; exit 1 ;; esac

if findmnt -rn -S /dev/sda4 >/dev/null; then echo "error: /dev/sda4 (/boot) is mounted; unmount it first" >&2; exit 1; fi
for t in curl bsdtar mkinitcpio pacman-key python3; do command -v $t >/dev/null || { echo "error: $t missing" >&2; exit 1; }; done
mkdir -p "$cache"; cd "$cache"

echo "== 1. packages from $URL"
curl -sfL -o omarchy.db "$URL/omarchy.db"
read -r kfile dfile < <(python3 -I - <<'EOF'
import tarfile, re
want = {'linux-omarchy': None, 'linux-omarchy-dtbs': None}
with tarfile.open('omarchy.db') as t:
    for m in t.getmembers():
        if not m.name.endswith('/desc'): continue
        txt = t.extractfile(m).read().decode() + '\n\n'
        g = lambda k: re.search('%' + k + '%\n(.*?)\n\n', txt, re.S).group(1)
        if g('NAME') in want: want[g('NAME')] = g('FILENAME')
print(want['linux-omarchy'], want['linux-omarchy-dtbs'])
EOF
)
[ -n "$kfile" ] && [ "$kfile" != None ] && [ "$dfile" != None ] || { echo "error: linux-omarchy not found in the repository database" >&2; exit 1; }
for f in "$kfile" "$dfile"; do
    [ -s "$f" ] || curl -fL --progress-bar -o "$f" "$URL/$f"
    curl -sfL -o "$f.sig" "$URL/$f.sig"
    pacman-key --verify "$f.sig" "$f" 2>&1 | grep -q 'Good signature' || { echo "error: bad signature on $f" >&2; exit 1; }
    echo "   $f: signature good"
done
bsdtar -tf "$kfile" > files.txt
rel=$(sed -n 's|^usr/lib/modules/\([^/]*\)/vmlinuz$|\1|p' files.txt)
[ -n "$rel" ] || { echo "error: no vmlinuz in $kfile" >&2; exit 1; }
case $rel in *omarchy*) ;; *) echo "error: unexpected release name $rel" >&2; exit 1 ;; esac
echo "$rel" > "$relfile"
bsdtar -tf "$dfile" | grep -q "/qcom/$dtb$" || { echo "error: $dtb is not in $dfile" >&2; exit 1; }

echo "== 2. modules -> /usr/lib/modules/$rel"
sudo -v
sudo rm -rf --one-file-system "/usr/lib/modules/$rel"
sudo bsdtar -xf "$kfile" -C / "usr/lib/modules/$rel"
sudo depmod "$rel"

echo "== 3. initramfs"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
# every Qualcomm platform driver the kernel has as a module, by directory
mods=$(grep -E "^usr/lib/modules/$rel/kernel/drivers/(clk/qcom|pinctrl/qcom|interconnect/qcom|phy/qualcomm|soc/qcom|pmdomain/qcom|firmware/qcom|ufs|spmi|reset|hwspinlock|power/sequencing)/.*\.ko" files.txt |
       sed -E 's|.*/||; s|\.ko.*$||' | sort -u | tr '\n' ' ')
more=$(grep -E "^usr/lib/modules/$rel/kernel/drivers/(regulator|mfd|nvmem|mailbox|irqchip|i2c/busses|gpio)/[^/]*(qcom|qfprom|geni|rpmh|spmi|shared)[^/]*\.ko" files.txt |
       sed -E 's|.*/||; s|\.ko.*$||' | sort -u | tr '\n' ' ')
cat > "$work/mkinitcpio.conf" <<EOF
# linux-omarchy on the Book4 Edge (tools/experiments/omarchy-kernel-test.sh)
MODULES=($mods $more
  pinctrl-x1e80100? qnoc-x1e80100? spmi-pmic-arb? pinctrl-spmi-gpio? i2c-qcom-geni?
  reset-gpio? gpio-shared-proxy? qcom_hwspinlock? smem? smp2p? socinfo? nvmem_qfprom?
  nvmem_qcom-spmi-sdam? qcom-cpucp-mbox? pci-pwrctrl-pwrseq? pwrseq-qcom-wcn? dwc3-qcom?
  rtc-pm8xxx? qcom-pon? pm8941-pwrkey? icc-bwmon? qcom_tsens? qcom-spmi-temp-alarm?
  ufs_qcom? ufshcd_pltfrm? phy_qcom_qmp_ufs? btrfs?)
BINARIES=()
FILES=()
HOOKS=(base systemd modconf block filesystems keyboard fsck)
EOF
echo "   $(wc -w <<<"$mods $more") platform modules named"
sudo mkinitcpio -k "$rel" -c "$work/mkinitcpio.conf" -g "$work/initramfs.img" > "$work/mkinitcpio.log" 2>&1 ||
    { grep -E '==> ERROR' "$work/mkinitcpio.log" | head -20; echo "   (mkinitcpio reported errors; continuing if the image has UFS)"; }
sudo chmod 644 "$work/initramfs.img"
LIST=$(lsinitcpio "$work/initramfs.img")
for m in ufs-qcom ufshcd-pltfrm phy-qcom-qmp-ufs gcc-x1e80100 pinctrl-x1e80100; do
    grep -qE "/$m\.ko" <<<"$LIST" || { echo "error: $m.ko missing from the initramfs" >&2; exit 1; }
done
echo "   $(du -h "$work/initramfs.img" | cut -f1) initramfs, UFS, clock and pin control inside"

echo "== 4. /boot and the GRUB entry"
bsdtar -xOf "$kfile" "usr/lib/modules/$rel/vmlinuz" > "$work/vmlinuz"
bsdtar -xOf "$dfile" "boot/dtbs/linux-omarchy/qcom/$dtb" > "$work/dtb"
b=$(mktemp -d); sudo mount /dev/sda4 "$b"
sudo install -m 644 "$work/vmlinuz" "$b/vmlinuz-$rel"
sudo install -m 644 "$work/initramfs.img" "$b/initramfs-$rel-arch.img"
sudo mkdir -p "$b/dtb-test"; sudo install -m 644 "$work/dtb" "$b/dtb-test/omarchy-edge-14.dtb"
sync; df -h "$b" | tail -1; sudo umount "$b"; rmdir "$b"
bash "$repo/install/arch/test-entry.sh" remove $name >/dev/null 2>&1 || true
bash "$repo/install/arch/test-entry.sh" add $name -mem_sleep_default -pcie_port_pm +qcom_aoss.prevent_aoss_sleep=1 \
    "kernel=/vmlinuz-$rel" "initrd=/initramfs-$rel-arch.img" dtb=/dtb-test/omarchy-edge-14.dtb
echo
echo "Installed linux-omarchy $rel as '... - test: $name'."
echo "Boot it at EL1:  sudo efibootmgr -n 0001 && systemctl reboot   (pick the entry in GRUB)"
echo "On that boot:    bash tools/experiments/omarchy-kernel-test.sh report"
