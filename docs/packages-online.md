# The [book4] repository online

The Book4 layer's packages are built on GitHub and published as a signed
pacman repository in this repository's release
[`repo`](https://github.com/n1c0la84/book4-edge-linux/releases/tag/repo):

| Package | What |
|---|---|
| `linux-book4`, `linux-book4-headers` | the kernel (n1c0la84/linux-book4-edge at the commit pinned as `_commit` in `packages/linux-book4/PKGBUILD`, config `packages/linux-book4/config`) |
| `book4-edge` | `userspace/`: audio, sleep, battery, keyboard, fingerprint import, ... |
| `book4-edge-boot` | `book4-boot` and its pacman hooks: kernels, initramfs, EL2 DTBs, Limine EL2 UKIs (`/boot`, `sda7`) and fallback Arch GRUB (`sda4`) |
| `book4-edge-el2` | the EL2 chain (UEFI Shell, qebspil, slbounce) and `book4-el2` (Limine and Arch GRUB chains) |
| `fastrpc` | Qualcomm's FastRPC userspace (`adsprpcd`, ...) at a pinned commit, without upstream's auto-start rules |
| `libssc-book4`, `iio-sensor-proxy-book4` | the ambient light sensor's reader, with Rafael Meneses' patches (replace Arch's `libssc`, `iio-sensor-proxy`) |
| `book4-sensors` | the ambient light sensor's setup and `book4-autobrightness` (`docs/sensors.md`); needs the locally built `book4-edge-firmware` |
| `libfprint-sdcp` | `libfprint` with SDCP v2 (MR !547) for the EgisTec `1c7a:05a1` fingerprint reader (replaces Arch's `libfprint`) |

**`book4-edge-firmware` is not there and never will be**: it holds files
from Windows (ADSP/CDSP/GPU firmware, tcblaunch.exe). Only its recipe is
public (`packages/book4-edge-firmware`, `install/arch/firmware-stage.sh`,
a checksum list); each laptop builds it from its own Windows partition.
This laptop also keeps a copy in a private repository on the home server's
share (`install/arch/book4-private.sh`: `publish` after a firmware build,
`install` on a fresh system; `/mnt/storage/BACKUPS/book4-private`, never
online, not in pacman.conf because an unreachable repository breaks
`pacman -Syu` away from home).

## Using it on a fresh install

```sh
# the repository's signing key (also in keys/book4-repo.asc)
curl -fsSLO https://raw.githubusercontent.com/n1c0la84/book4-edge-linux/main/keys/book4-repo.asc
sudo pacman-key --add book4-repo.asc
sudo pacman-key --lsign-key E75AAB6A080DCE59DC84259D595D834A7E98BBCE

printf '[book4]\nSigLevel = Required\nServer = https://github.com/n1c0la84/book4-edge-linux/releases/download/repo\n' |
    sudo tee /etc/pacman.d/book4-repo.conf
echo 'Include = /etc/pacman.d/book4-repo.conf' | sudo tee -a /etc/pacman.conf
sudo pacman -Syu
sudo pacman -S linux-book4 book4-edge book4-edge-boot book4-edge-el2 libfprint-sdcp

# the firmware, from this laptop's Windows partition (set BOOK4_FW_LOCAL=<dir>
# for the four ath12k c5-00302 Wi-Fi files on a fresh install; docs/firmware.md)
git clone https://github.com/n1c0la84/book4-edge-linux && cd book4-edge-linux
bash install/arch/firmware-stage.sh
(cd packages/book4-edge-firmware && makepkg -f && sudo pacman -U --overwrite '/usr/lib/firmware/updates/*' book4-edge-firmware-*.pkg.tar.zst)

# optional: ambient light sensor and automatic brightness
sudo pacman -S book4-sensors
```

Then `/etc/book4/boot.conf` (`install/arch/book4-boot-setup.sh`),
`sudo book4-el2 install` and `sudo book4-el2 install-limine`, as on the laptop
today.

The laptop that made all this keeps its local `[book4]` (`install/arch/book4-repo.sh`)
until it is reinstalled; nothing on it uses the online repository.

## Building and publishing

GitHub Actions, workflow `packages` (`.github/workflows/packages.yml`),
started by hand: Actions > packages > Run workflow, or

```sh
gh workflow run packages                                   # all of them
gh workflow run packages -f packages="book4-edge book4-edge-boot"
```

It runs on GitHub's arm64 runner inside an Arch Linux ARM container made
from the official root filesystem (signature checked against the Arch Linux
ARM Build System key, `keys/archlinuxarm-build-system.asc`), builds the
packages unsigned as an unprivileged `builder` user (without access to the
signing key), checks `.BUILDINFO`/`.PKGINFO`, then signs the packages and
updates the repository database as root (`.github/scripts/build-packages.sh`,
dropping the older build of each) and uploads packages and signatures before
the repository database. The kernel takes the longest (the run's limit is
350 minutes). A build fails if a package's build metadata (`.BUILDINFO`,
`.PKGINFO`) names a home directory other than the build user's (local builds
record their own; package contents come from public sources and do mention
upstream developers' homes, so they are not scanned). The kernel took about
70 minutes on 20 November.

Before a kernel build: bump `pkgver`/`pkgrel` and `_commit` in
`packages/linux-book4/PKGBUILD`, push the kernel branch, and refresh
`packages/linux-book4/config` if the config changed. `book4-edge`,
`book4-edge-boot` and `book4-sensors` take their version from the commit count.

## The signing key

`E75AAB6A080DCE59DC84259D595D834A7E98BBCE` "Book4 Edge Linux packages"
(ed25519, sign only, no expiry), created 20 November 2026 in memory on the
laptop. The private key exists only as the repository secret
`BOOK4_SIGN_KEY` (fingerprint in the variable `BOOK4_SIGN_FPR`); no copy
was kept. A secret cannot be read back, so if it is ever lost or exposed:
make a new key the same way, replace the secret, the variable and
`keys/book4-repo.asc`, rebuild everything, and re-import the key on each
machine (`pacman-key --delete` the old one).
