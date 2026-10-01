# The kernel: QSEECOM, and the quirks we do not carry

Three patches exist upstream (in [Anatase](https://github.com/anatase-org/patchwork))
that this machine would benefit from and that we do **not** have, because all
three are compiled into the kernel rather than loadable as modules. This is the
analysis of whether that is worth acting on, and how.

Short answer: **do not rebuild the kernel. Use Anatase's prebuilt RPMs** — but
report our `samsung-emuec` patch to them first, or we lose it.

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

## The recommendation, and the order

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
