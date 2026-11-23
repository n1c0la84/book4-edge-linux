# The [book4] repository online

The Book4 layer's packages are built on GitHub and published as a signed
pacman repository in this repository's release
[`repo`](https://github.com/n1c0la84/book4-edge-linux/releases/tag/repo):

| Package | What |
|---|---|
| `linux-book4`, `linux-book4-headers` | the kernel (n1c0la84/linux-book4-edge at the commit pinned as `_commit` in `packages/linux-book4/PKGBUILD`, config `packages/linux-book4/config`) |
| `book4-edge` | `userspace/`: audio, sleep, battery, keyboard, fingerprint import, ... |
| `book4-edge-boot` | `book4-boot` and its pacman hooks: kernels and the GRUB menu on /boot |
| `book4-edge-el2` | the EL2 chain (UEFI Shell, qebspil, slbounce) and `book4-el2` |
| `fastrpc` | Qualcomm's FastRPC userspace (`adsprpcd`, ...) at a pinned commit, without upstream's auto-start rules |
| `libssc-book4`, `iio-sensor-proxy-book4` | the ambient light sensor's reader, with Rafael Meneses' patches (replace Arch's `libssc`, `iio-sensor-proxy`) |
| `book4-sensors` | the ambient light sensor's setup (`docs/sensors.md`); needs the locally built `book4-edge-firmware` |

**`book4-edge-firmware` is not there and never will be**: it holds files
from Windows (ADSP/CDSP/GPU firmware, tcblaunch.exe). Only its recipe is
public (`packages/book4-edge-firmware`, `install/arch/firmware-stage.sh`,
a checksum list); each laptop builds it from its own Windows partition.

## Using it on a fresh install

```sh
# the repository's signing key (also in keys/book4-repo.asc)
curl -fsSLO https://raw.githubusercontent.com/n1c0la84/book4-edge-linux/main/keys/book4-repo.asc
sudo pacman-key --add book4-repo.asc
sudo pacman-key --lsign-key E75AAB6A080DCE59DC84259D595D834A7E98BBCE

printf '[book4]\nSigLevel = Required\nServer = https://github.com/n1c0la84/book4-edge-linux/releases/download/repo\n' |
    sudo tee /etc/pacman.d/book4-repo.conf
echo 'Include = /etc/pacman.d/book4-repo.conf' | sudo tee -a /etc/pacman.conf
sudo pacman -Sy linux-book4 book4-edge book4-edge-boot book4-edge-el2

# the firmware, from this laptop's Windows partition
git clone https://github.com/n1c0la84/book4-edge-linux && cd book4-edge-linux
bash install/arch/firmware-stage.sh
(cd packages/book4-edge-firmware && makepkg -f && sudo pacman -U book4-edge-firmware-*.pkg.tar.*)
```

Then `/etc/book4/boot.conf` (`install/arch/book4-boot-setup.sh`) and
`sudo book4-el2 install`, as on the laptop today.

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
ARM Build System key, `keys/archlinuxarm-build-system.asc`), builds with
`makepkg --sign` (`.github/scripts/build-packages.sh`), adds the packages
to the repository database (the older build of each is dropped) and uploads
everything to the release. The kernel takes the longest (the run's limit is
350 minutes). A build fails if a package's build metadata (`.BUILDINFO`,
`.PKGINFO`) names a home directory other than the build user's (local builds
record their own; package contents come from public sources and do mention
upstream developers' homes, so they are not scanned). The kernel took about
70 minutes on 20 November.

Before a kernel build: bump `pkgver`/`pkgrel` and `_commit` in
`packages/linux-book4/PKGBUILD`, push the kernel branch, and refresh
`packages/linux-book4/config` if the config changed. `book4-edge` and
`book4-edge-boot` take their version from the commit count.

## The signing key

`E75AAB6A080DCE59DC84259D595D834A7E98BBCE` "Book4 Edge Linux packages"
(ed25519, sign only, no expiry), created 20 November 2026 in memory on the
laptop. The private key exists only as the repository secret
`BOOK4_SIGN_KEY` (fingerprint in the variable `BOOK4_SIGN_FPR`); no copy
was kept. A secret cannot be read back, so if it is ever lost or exposed:
make a new key the same way, replace the secret, the variable and
`keys/book4-repo.asc`, rebuild everything, and re-import the key on each
machine (`pacman-key --delete` the old one).
