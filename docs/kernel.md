# The kernel: QSEECOM, and the quirks we do not carry

Three patches exist upstream (in [Anatase](https://github.com/anatase-org/patchwork))
that this machine would benefit from and that we do **not** have, because all
three are compiled into the kernel rather than loadable as modules. This is the
analysis of whether that is worth acting on, and how.

Short answer, revised 1 October: **build Anatase's tree locally.** Taking their
prebuilt RPMs was the earlier recommendation and it is no longer the better one,
because their tree restructured on 30 September — the battery driver became a
full EC platform driver, the device tree compatible changed, and a DTB or DKMS
package from the day before no longer matches. Building the whole thing from one
tree keeps the kernel, the drivers and the device tree in step, carries our own
`samsung-emuec` patch, and lets us follow a tree that is moving daily.

## What each patch actually buys

### 1. The QSEECOM allowlist — the only one that matters

    firmware: qcom: scm: Allow QSEECOM on the Samsung Galaxy Book4 Edge

`drivers/firmware/qcom/qcom_scm.c` carries `qcom_scm_qseecom_allowlist[]`, and
our compatible is not in it, so `dmesg` says:

    qcom_scm: qseecom: untested machine, skipping

Without QSEECOM, `qcom_qseecom_uefisecapp` never registers and `efivars` stays
empty. That costs us **two** things, not one:

- **`efibootmgr` cannot create NVRAM boot entries** — "EFI variables are not
  supported on this system". We work around it with `bcdedit` from Windows.
- **The RTC.** This is not a guess. The device tree's RTC node is:

        rtc@6100 {
            compatible = "qcom,pmk8350-rtc";
            qcom,no-alarm;
            qcom,uefi-rtc-info;     <-- here
        };

  `qcom,uefi-rtc-info` tells the driver the RTC offset lives in a **UEFI
  variable**. The PMIC counter alone has no epoch. No efivars, no offset, so
  the clock comes up at a fixed wrong date every boot. The two symptoms have
  one cause.

Anatase's patch matches on `samsung,galaxy-book4-edge`, our *second*
compatible, so one line covers the 14" and the 16".

**There is no module shortcut.** The allowlist is a `static const` table in
`qcom_scm.c`, which is builtin (it is needed far too early to be a module), and
there is no module parameter. Either the kernel is rebuilt or it is replaced.

### 2. The UFS Kioxia quirk — cosmetic, ignore it

    ufs: core: skip unsupported timestamp on Kioxia THGJFJT2T85BAT0A

Three lines adding our disk to `ufs_fixups[]` with
`UFS_DEVICE_QUIRK_NO_TIMESTAMP_SUPPORT`. An almost identical entry already
exists for `THGJFJT1E45BATP`.

What the quirk does, in `ufshcd_set_timestamp_attr()`:

    if (dev_info->wspecversion < 0x400 ||
        hba->dev_quirks & UFS_DEVICE_QUIRK_NO_TIMESTAMP_SUPPORT)
            return;

UFS 4.0 lets the host tell the device the current time, for the device's own
internal logging. Some devices advertise the feature and then reject the
command. Without the quirk the kernel sends the query, gets an error and logs
it, at init and on every resume.

**It touches no data, no performance, no reliability.** It silences a log line.
It is not a reason to do anything; it is a reason to carry the patch along if a
rebuild happens for another cause. If UFS errors appear at boot, this is them,
and they are harmless.

### 3. The HID keyboard quirk — marginal

    HID: add multi-input quirk for Galaxy Book4 Edge keyboard

Anatase's in-kernel version of what we solve with
[userspace/keyboard/99-book4-keyboard.rules](../userspace/keyboard). Ours works.
The kernel quirk is the better long-term home — see
[upstream.md](upstream.md), where a systemd hwdb entry is proposed so that every
distribution gets it without a kernel patch — but there is nothing to gain by
switching today.

## Earlier recommendation: Anatase's prebuilt RPMs (superseded, see below)

Rebuilding a Fedora kernel for one line is a lot of machinery. Anatase already
publishes kernel RPMs with **all three patches plus the two drivers built in**,
as a container image:

    podman pull ghcr.io/anatase-org/kernel:f44-aarch64
    podman create --name ak ghcr.io/anatase-org/kernel:f44-aarch64 /bin/true
    podman cp ak:/rpms ./anatase-rpms
    podman rm ak

The image is `FROM scratch`: it holds `/rpms` and `/srpms` and nothing else.
Note it is built for **Fedora 44** while we run 45; kernel packages have few
dependencies and this is expected to be fine, but it is untested here.

Switching to it means:

- QSEECOM, the UFS quirk and the HID quirk, for free
- the battery and Type-C drivers **in-tree**, so the DKMS package must be
  removed or it will conflict
- tracking Anatase's releases instead of Fedora's kernels
- **losing our PD retry patch**, because it is not in their tree

That last point sets the order:

1. **Report the PD retry patch to Anatase** ([patches/0001](../drivers/anatase/patches),
   [upstream.md](upstream.md)) and give them a chance to take it.
2. Then switch to their kernel.
3. Then remove our DKMS package and verify charging still survives a hot replug
   — that is the regression to watch for, and the only one.

Doing it in the other order trades a working charger for a working clock.

## Building it locally (revised recommendation, 1 October)

Everything comes from one tree, so nothing can skew:

    sudo dnf install -y gcc make flex bison bc openssl-devel \
        elfutils-libelf-devel ncurses-devel dwarves perl rsync

    git clone --depth 1 -b anatase-7.2 \
        https://github.com/anatase-org/patchwork.git
    cd patchwork
    patch -p1 < .../0001-samsung-emuec-retry-PD-request-after-hot-plug.patch

    cp /boot/config-$(uname -r) .config
    make olddefconfig
    ./scripts/config --module EC_SAMSUNG_GALAXYBOOK
    ./scripts/config --module TYPEC_SAMSUNG_EMUEC
    make olddefconfig

    make -j$(nproc)            # ~12 cores here, 1-3 hours
    sudo make modules_install
    sudo make install

Three things that bite:

- **The device tree now comes from the kernel tree**, `arch/arm64/boot/dts/qcom/`,
  not from `/usr/lib/firmware/book4/`. `userspace/boot/99-book4-devicetree.install`
  must be updated to take the newly built one, or a new kernel gets an old DTB
  whose compatibles no longer match the drivers.
- **Remove the DKMS package first**, or two drivers fight over the same EC.
- About 25 GB of disk for the build tree.

The honest cost is that a local build buys the rebuilds forever: every kernel
security update becomes our work rather than someone else's. We are already
running a kernel-install hook and pinning a default kernel, so this is not a new
kind of burden — but it is more of it.

## Our branch: n1c0la84/linux-book4-edge (6 October)

The kernel stays Anatase's tree plus our patches, now as a public branch:
**https://github.com/n1c0la84/linux-book4-edge/tree/book4/7.2**, a fork of
`anatase-org/patchwork`. `book4/7.2` is Anatase `2ad788424` plus eight
commits, made by [`install/kernel-branch.sh`](../install/kernel-branch.sh)
from the patch files in this repo:

| commit | from |
|---|---|
| hamoa: add CCI0 and CAMSS; enable the front camera; add tweeters; enable the fingerprint reader (8 Oct) | `dts/patches/0001-0004` |
| samsung-emuec: PD retry; quiesce across sleep; wake on plug-in | `drivers/anatase/patches/0001-0003` |
| `arch/arm64/configs/book4_edge_defconfig` | the running 7.2.7-book4 config |

Build: `git switch book4/7.2 && make LOCALVERSION= book4_edge_defconfig`.

Checked against what runs ([`tools/kernel/check-branch.sh`](../tools/kernel/check-branch.sh),
6 October): `samsung-emuec.c` identical to the installed module's source;
the device tree identical in content to the default four-speaker DTB
([`tools/kernel/dtb-compare.py`](../tools/kernel/dtb-compare.py) compares by
content, since dtc -@ and source order change the bytes and phandle numbers)
except three empty CAMSS ports (`port@1-3`), which the CAMSS patch as sent to
Anatase describes and the separately built DTB omitted.

Rules: one branch per series, rebased when Anatase moves; every patch also
goes to Anatase, so the branch only carries what they have not taken; the
patch files here stay the source. Built from Arch through the Fedora
container (`install/arch/fedora-shell.sh`), which this was the first real
use of.

## Done: 1 October 2026

Built and running: `7.2.7-book4` from `anatase-org/patchwork` branch `anatase-7.2`
(head `2ad788424`), plus our PD retry patch (branch `book4/pd-retry`, reported in
https://github.com/anatase-org/kernel-anatase/issues/1).

What it took, on the laptop itself:

    git clone --depth 1 -b anatase-7.2 https://github.com/anatase-org/patchwork.git
    cd patchwork
    git submodule update --init --depth 1     # drivers/custom/* Kconfig needs them
    git am / patch -p1 < our PD retry patch
    cp /boot/config-7.2.0-61.fc45.aarch64 .config && make olddefconfig
    ./scripts/config --module EC_SAMSUNG_GALAXYBOOK --module TYPEC_SAMSUNG_EMUEC \
        --enable DEBUG_INFO_NONE --disable DEBUG_INFO_BTF \
        --set-str LOCALVERSION "-book4" --disable LOCALVERSION_AUTO
    make olddefconfig
    systemd-inhibit --what=sleep:idle:handle-lid-switch make -j12 LOCALVERSION= all
    bash install/install-anatase-kernel.sh

- `LOCALVERSION=` on every make call drops the `+` for an untagged tree, so the
  release is exactly `7.2.7-book4`.
- Debug info off: the build took **25 minutes** on the 12 cores (no `pahole`
  needed). `perl` and `ncurses-devel` were not needed either.
- `install/install-anatase-kernel.sh` restricts our DKMS packages to Fedora
  kernels (`BUILD_EXCLUSIVE_KERNEL`), otherwise their copies in `extra/` would
  shadow the built-in drivers; installs modules and `dtbs_install` into
  `/usr/lib/modules/<kver>/dtb`; and runs `make install`, which on Fedora is
  `kernel-install` (dracut + our hook). The hook now prefers a Book4 DTB
  shipped with the kernel and re-pads it with `dtc -p 8192`.
- The kernel is added as an "(other)" GRUB entry; the pinned default stays the
  Fedora kernel until it is pinned (`/etc/book4/default-kernel`).

Verified on the 14": display (GPU accelerated, Adreno X1-85), keyboard,
touchpad, Wi-Fi, Bluetooth, audio devices, battery and AC through
`samsung-galaxybook-ec` (charging confirmed), USB-C and a charger hot replug
back at 20 V, the keyboard backlight and its Fn hotkey, EFI variables
(`efibootmgr` works). Kernel not tainted. The RTC is now readable but wrong
(2024-05-30) until written once.

Harmless: `failed to load gen70500_sqe.fw` early in boot; the GPU loads it
from the root filesystem ~16 s later.

### Clock (RTC), set 1 October

The RTC (`rtc-pm8xxx`, `qcom,uefi-rtc-info`) read 2024-05-30 on the first
boot. Convention chosen: **UTC in the hardware clock** for both systems.

- Linux (already `RTC in local TZ: no`): `sudo hwclock --systohc --utc`. The
  RTC then matched UTC to the second; the offset is kept in the UEFI variable
  `RTCInfo-882f8c2b-9646-435f-8de5-f208ff80c1bd`.
- Windows, once, in an administrator Command Prompt, then restart:
  `reg add "HKLM\System\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f`
  Without it Windows reads the clock as local time (2 h off in Rome in
  summer) and may write local time back.

Verified after a reboot: `rtc-pm8xxx ... setting system clock to
2026-10-01T15:42:08 UTC` at 1.9 s, correct, and chrony only selected an NTP
source at 24 s. Log lines from the first ~1.9 s (before the RTC module loads)
still carry systemd's fallback date.

### Default since 1 October

`/etc/book4/default-kernel` = `7.2.7-book4`. Menu: 7.2.7-book4 (default),
7.2.7-book4 verbose, 7.2.0-61 "(other)" (its own DTB from
`/usr/lib/firmware/book4/` plus the DKMS drivers), Windows, firmware settings.
The "alt DT book4-own.dtb" entry was removed (`/etc/book4/test-dtb` deleted):
it always uses the default kernel, and the new kernel's drivers do not match
that older device tree.

**Not across a flat battery.** After the battery ran empty overnight
(1-2 October) the kernel set the clock to 2026-09-30 11:44 on the next boot;
chrony corrected it once online. The RTC counter evidently stops when the
battery is fully drained.

### Known problem: suspend drains the battery (2 October)

On this kernel s2idle does not reach the SoC low-power states, so a night with
the lid closed empties the battery. Details and the test in
[power.md](power.md).

