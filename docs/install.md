# Reproducing this machine

How the Samsung Galaxy Book4 Edge 14" (NP940XMA) is set up as of
**26 November 2026**: **Arch Linux ARM + Omarchy 4.5** as the daily system,
booted at **EL2** via **Limine + EL2 UKIs** with our packaged `linux-book4`
(`7.3.4-book4`) kernel and the Book4 layer packages from the signed online
`[book4]` repository ([packages-online.md](packages-online.md)).

> **Note:** Fedora was used during the original October 2026 bring-up and was
> retired/deleted on 23 November 2026 ([fedora-retired.md](fedora-retired.md)).
> Legacy Fedora scripts remain in `install/` as history; the current setup is
> Arch-native. Every piece below runs on the reference machine, though the full
> sequence from a blank disk has not been run end-to-end.

## What you need first

- **Windows, kept on `sda3`.** The ADSP/CDSP/GPU firmware, `tcblaunch.exe` (for
  EL2), ambient light sensor config/registry, firmware updates, and Windows
  Hello fingerprint enrolments all come from Windows ([firmware.md](firmware.md)).
- **Disk layout on the reference machine:**
  - `sda1` (260 MiB FAT32, `/efi`): firmware & Windows ESP — holds the UEFI
    Shell EL2 chains (`\EFI\book4-el2-limine\`, `\EFI\book4-el2-arch\`) and
    `qebspil`'s `\firmware\...` copy. **Only add or update our folders; never
    delete Windows or firmware files.**
  - `sda3` (NTFS): Windows.
  - `sda4` (512 MiB ext4, unmounted normally): fallback Arch GRUB `/boot`.
  - `sda5` + `sda6` (btrfs, two-device root): Arch/Omarchy subvolume (`arch-45`).
  - `sda7` (1.5 GiB FAT32, label `BOOK4ESP`, `/boot`): second ESP for Limine,
    `limine.conf`, and EL2 UKIs (`/EFI/Linux/book4-*-el2.efi`).
- **Four non-Windows Wi-Fi firmware files (`c5-00302`)**: from Debian
  `firmware-atheros` 20251111-1 + extracted `board.bin` ([firmware.md](firmware.md)).
  Keep a local copy to pass via `BOOK4_FW_LOCAL=<dir>` on a fresh install.

## 1. Base Arch Linux ARM + Omarchy

Start from an Arch Linux ARM + Omarchy 4.5 installation (or Omarchy's official
Snapdragon ISO once available; see [ROADMAP.md](ROADMAP.md) and
[arch.md](arch.md) for how this machine was originally bootstrapped).

Before installing `linux-book4`, keep `linux-modules-cleanup.service` masked if
you keep more than one kernel installed, and never run
`omarchy-reinstall-configs`, `omarchy-refresh-limine`,
`omarchy-setup-security-fingerprint`, or Omarchy's x86 `post-install/pacman.sh`.

## 2. Add the signed `[book4]` repository and install the Book4 layer

See [packages-online.md](packages-online.md) for full details on key
verification and CI builds:

```sh
curl -fsSLO https://raw.githubusercontent.com/n1c0la84/book4-edge-linux/main/keys/book4-repo.asc
sudo pacman-key --add book4-repo.asc
sudo pacman-key --lsign-key E75AAB6A080DCE59DC84259D595D834A7E98BBCE

printf '[book4]\nSigLevel = Required\nServer = https://github.com/n1c0la84/book4-edge-linux/releases/download/repo\n' |
    sudo tee /etc/pacman.d/book4-repo.conf
echo 'Include = /etc/pacman.d/book4-repo.conf' | sudo tee -a /etc/pacman.conf

sudo pacman -Syu
sudo pacman -S linux-book4 book4-edge book4-edge-boot book4-edge-el2 \
    libfprint-sdcp limine systemd-ukify python-pefile
```

*(On the reference machine itself, a local unsigned `[book4]` repository at
`/var/lib/book4-repo` managed by `install/arch/book4-repo.sh` is used instead
of the online release.)*

## 3. Build and install `book4-edge-firmware` (local only)

Proprietary Windows/Qualcomm firmware and `tcblaunch.exe` are never published.
Stage them read-only from this laptop's Windows partition (pass
`BOOK4_FW_LOCAL=<dir>` containing `ath12k/WCN7850/hw2.0/{amss.bin,m3.bin,board.bin,board-2.bin}`
on a fresh install; `qcom/gen70500_sqe.fw` is picked up from `linux-firmware-qcom`):

```sh
git clone https://github.com/n1c0la84/book4-edge-linux && cd book4-edge-linux
BOOK4_FW_LOCAL=/path/to/wifi-fw-backup bash install/arch/firmware-stage.sh
(cd packages/book4-edge-firmware && makepkg -f && \
    sudo pacman -U --overwrite '/usr/lib/firmware/updates/*' book4-edge-firmware-*.pkg.tar.zst)
```

Optional: ambient light sensor and automatic brightness ([sensors.md](sensors.md)):

```sh
sudo pacman -S book4-sensors
systemctl --user enable --now book4-autobrightness
```

## 4. Enable the Book4 services

Arch packages do not enable systemd units automatically:

```sh
sudo systemctl enable book4-bt-addr book4-fingerprint-import book4-live-log book4-el2-sleep
systemctl --user enable --now book4-battery-warn.timer book4-gpu-busy book4-drain
```

For Bluetooth's public address, extract it once from Windows with
`tools/bt-address-from-windows.py` into `/etc/book4/bt-address`.
For fingerprints, enroll in Windows Hello and `book4-fingerprint-import` will
import the records on boot; configure PAM for `sudo` and
`/etc/pam.d/omarchy-lock-fingerprint` (never run
`omarchy-setup-security-fingerprint`, which replaces `libfprint-sdcp`).

## 5. Bootloader and EL2 chain

1. Create `/etc/book4/boot.conf` from `/usr/share/book4/boot.conf.example` (or
   run `bash install/arch/book4-boot-setup.sh`), and ensure `sda7` (`BOOK4ESP`)
   is mounted at `/boot` and `sda1` at `/efi` in `/etc/fstab`.
2. Populate `/boot` (Limine EL2 UKIs + `limine.conf`) and fallback Arch GRUB:
   `sudo book4-boot menu` (also triggered automatically by pacman hooks on
   kernel/initramfs/overlay/Limine updates).
3. Install the EL2 chains onto `/efi` (`sda1`) and create firmware boot entries
   outside `BootOrder` first ([el2.md](el2.md), [plan-limine.md](plan-limine.md)):
   ```sh
   sudo book4-el2 install          # \EFI\book4-el2-arch\ (qebspil, slbounce, tcblaunch, Arch GRUB fallback)
   sudo book4-el2 install-limine   # \EFI\book4-el2-limine\ (starts Limine on BOOK4ESP)
   ```
4. Test the new Limine firmware entry once with `efibootmgr --bootnext XXXX`.
   Confirm `/dev/kvm`, `book4-el2 status`, ADSP/CDSP attached, audio, and
   `s2idle` deep sleep (`journalctl -t book4-sleep`) before putting it first in
   `BootOrder`.

## Backup and recovery

- **Full Linux backup to an external drive or mounted share:**
  `bash tools/backup/linux-backup.sh /path/to/mounted/drive` (snapshots the
  running btrfs subvolume, backs up `/boot` (`sda7`), fallback `sda4`, Linux/EL2
  files + `firmware/` on `sda1`, `efibootmgr -v`, and the partition table, and
  writes `RESTORE.md`).
- **Pre-update btrfs snapshots:** `bash tools/backup/snapshot-arch.sh` (also run
  automatically by `book4-update`).
- **Firmware boot menu:** press **F10** at power-on to pick Arch GRUB fallback,
  EL1, or Windows.
- **Note on `live-iso.sh` / `book4-install.sh` / `rescue-usb.sh`:** those
  October scripts still target the pre-23-Nov `arch` subvolume / `sda4` GRUB
  layout and need updating before reuse on the current disk layout.
