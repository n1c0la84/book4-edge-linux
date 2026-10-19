# Experiments (October 2026)

The one-off test and preparation scripts behind [docs/power.md](../../docs/power.md),
[docs/el2.md](../../docs/el2.md) and [docs/windows-investigation.md](../../docs/windows-investigation.md),
run from the home folder between 14 and 19 October 2026 and kept here as the
record of what was tried. **Not maintained:** they assume they live in `~`
(they call each other as `~/name.sh`), name GRUB test entries and kernels that
may no longer exist, and several change boot entries or hardware state. Read a
script and its section in the docs before running it. The few still in use
were promoted: `tools/power/el2-drain-test.sh`, `tools/power/dsp-sleep-stats.sh`,
`tools/backup/snapshot-arch.sh`, `install/arch/mount-ro.sh`,
`install/arch/boot-defaults.sh`; `blacklist-pwrlmts.sh` became part of
`install/el2/sleep-setup.sh`, `ignore-mkinitcpio.sh` of `install/arch/stage3-yay.sh`.

Known dangerous on this machine (each reset it): `rscc-dump.sh` stage 2 (the
20 KB display RSC sweep), `rpmh-read-test.sh` (`rpmh_read()` hangs X1E), and
`el2-audio-off-test.sh` in its first version (unbinding `lpasscc-sc8280xp`;
also never read `clk_summary` once LPASS is powered down).

| Script | What it tested |
|---|---|
| [`blacklist-pwrlmts.sh`](blacklist-pwrlmts.sh) | The Windows "Modern Standby" message (qcom_adsp_pwr_lmts, from x1e-sleep) crashes the Book4's ADSP at every suspend (19 Oct: EX:kernel:0x1:ipcc_irq121). |
| [`bt-unbind-test.sh`](bt-unbind-test.sh) | Is the Bluetooth UART the last XO holder? |
| [`cleanup-power-tests.sh`](cleanup-power-tests.sh) | Remove the 14-15 October suspend-drain test material (the tools are in the repo now). |
| [`clk-at-suspend.sh`](clk-at-suspend.sh) | Which clocks are still enabled when the SoC goes to sleep? |
| [`drips-noflags-readd.sh`](drips-noflags-readd.sh) | (Re-)add the GRUB test entry "drips-noflags": normal boot (EL1, Gunyah), DRIPS DTB, without clk_ignore_unused/pd_ignore_unused. |
| [`drips-nowifi-prep.sh`](drips-nowifi-prep.sh) | Prepare the maximal DRIPS test: DRIPS DTB with the Wi-Fi PCIe controller (pci@1c08000) and its PHY disabled, no clk/pd_ignore_unused. |
| [`drips-pd-el1-prep.sh`](drips-pd-el1-prep.sh) | EL1 entry for the DRIPS-with-power-down-bit DTB (book4-drips-pd.dtb, 0x4200c354, already in /boot/dtb-test from el2-variants-prep.sh): GRUB test entry "drips-pd |
| [`drips-pd-gpio44-prep.sh`](drips-pd-gpio44-prep.sh) | EL1 entry "drips-pd-mods": the DRIPS-with-power-down-bit DTB with GPIO 44 (EC "standby" input MODS) no longer reserved (gpio-reserved-ranges <35 1>, <45 3> inst |
| [`drips-sync-prep.sh`](drips-sync-prep.sh) | Prepare the "DRIPS + released boot votes" test (16 October): 1. |
| [`drips-sync-run.sh`](drips-sync-run.sh) | Run on the "test: drips-noflags" boot, on battery, as yourself: bash ~/drips-sync-run.sh Holds an active-only UFS vote (tag=3, dropped by RPMh in sleep; this is |
| [`drips-test.sh`](drips-test.sh) | Install the DRIPS test DTB and a GRUB test entry for it ("test: drips"). |
| [`dsp-stop-test.sh`](dsp-stop-test.sh) | Linux's own RPMh votes are all off at sleep (16 Oct clean trace), yet the SoC never collapses. |
| [`el2-adsponly-prep.sh`](el2-adsponly-prep.sh) | Which DSP's sleep votes keep CX up? |
| [`el2-audio-off-test.sh`](el2-audio-off-test.sh) | On "test: el2-sleep" with the DSPs attached, ON BATTERY: does Linux's audio stack keep CX up through the ADSP? |
| [`el2-drips-prep.sh`](el2-drips-prep.sh) | EL2 deep-sleep test prep: install the DRIPS DTB's EL2 variant (/boot/dtb-test/book4-drips-el2.dtb) and the GRUB test entry "el2-drips" (no clk/pd_ignore_unused, |
| [`el2-drips-readd.sh`](el2-drips-readd.sh) | Re-add the GRUB test entry "el2-drips": EL2, PSCI OSI hierarchy, DRIPS 0x0200c354 (no power-down bit) on the system domain. |
| [`el2-dsp-prep.sh`](el2-dsp-prep.sh) | EL2 with DSPs, without the USB stick. |
| [`el2-pcmode-prep.sh`](el2-pcmode-prep.sh) | PSCI platform-coordinated (PC) mode at EL2, as under Windows/Hyper-V (which never switch TrustZone to OS-initiated mode). |
| [`el2-pdc-prep.sh`](el2-pdc-prep.sh) | GRUB test entry "el2-pdc": the 7.3 PDC backport kernel at EL2 (slbounce), EL2 variant of /dtb-test/book4-pdc.dtb (upstream domain_ss3 in the OSI hierarchy). |
| [`el2-pdc-test.sh`](el2-pdc-test.sh) | On "test: el2-pdc": PDC mode, then switch off the known EL2 artifact (the EL1 virtual timer left armed on CPU 0, timer_check disable=1), then one probe suspend  |
| [`el2-probe.sh`](el2-probe.sh) | One probe of a system idle state (works at EL1 or EL2): releases the boot votes, unbinds Bluetooth, then one ~30 s suspend, and reports how often the system dom |
| [`el2-sleep-prep.sh`](el2-sleep-prep.sh) | The x1e-sleep recipe on the Book4: the sleep test kernel 7.2.7-book4s at EL2 (slbounce) with el1tmr. |
| [`el2-sleep-test.sh`](el2-sleep-test.sh) | On "test: el2-sleep": the x1e-sleep recipe (book4s kernel at EL2, el1tmr programs the EL1 physical timer with the next deadline before power-down and clears the |
| [`el2-variants-prep.sh`](el2-variants-prep.sh) | Install the SS1, SS2 and DRIPS-with-power-down-bit DTBs to /boot/dtb-test, build their EL2 variants and add three GRUB test entries: "el2-ss1"      system state |
| [`gic-test.sh`](gic-test.sh) | On "test: el2-drips": what is pending in the GIC when CPUs come back from deep idle during suspend? |
| [`grub-cleanup.sh`](grub-cleanup.sh) | Tidy the GRUB menu: remove every test entry (book4-extra.cfg on /boot) except the ones still in use, and show what else is in the menu. |
| [`hibernate-pmtest.sh`](hibernate-pmtest.sh) | Find where hibernation resets the machine: run it only up to one stage and come straight back (pm_test), with the DSPs stopped first as the real hibernation doe |
| [`hyperv-fetch.sh`](hyperv-fetch.sh) | Copy Windows' hypervisor and the kernel/HAL that issue PSCI from the Windows partition (mounted READ-ONLY by ~/mount-ro.sh) into ~/src/hyperv-re/bin. |
| [`ignore-mkinitcpio.sh`](ignore-mkinitcpio.sh) | Hold mkinitcpio at its current version: add it to IgnorePkg in /etc/pacman.conf. |
| [`install-omarchy-qt612.sh`](install-omarchy-qt612.sh) | Install omarchy 4.0.4-3: v4.0.4 + book4 battery fixes + backport of upstream b83d3df (qualify the Color singleton so the shell works on Qt 6.12). |
| [`irq-during-suspend.sh`](irq-during-suspend.sh) | At EL2 the system power domain is entered ~16 000 times per second during s2idle: something brings the CPUs straight back. |
| [`make-el2-usb.sh`](make-el2-usb.sh) | Write the EL2 Secure-Launch test stick (UEFI Shell + sltest.efi + tcblaunch). |
| [`pcie-d3cold-check.sh`](pcie-d3cold-check.sh) | On the "test: drips-pcie" boot: one short suspend (wake it after ~1 min), then show whether the PCIe controller went through D3cold (a fresh "link up" after res |
| [`pcie-d3cold-prep.sh`](pcie-d3cold-prep.sh) | GRUB test entry "drips-pcie": DRIPS DTB, no clk/pd_ignore_unused, plus pcie_port_pm=force so the Wi-Fi root port may enter D3hot in suspend; then the kernel's o |
| [`pwrlmts-v2.sh`](pwrlmts-v2.sh) | qcom_adsp_pwr_lmts v2 (Windows' Modern Standby message from a PM notifier): rebuild the sleep kernel's modules and lift the blacklist of the v1. |
| [`qebspil-swap.sh`](qebspil-swap.sh) | Put a qebspil variant on the ESP (\EFI\book4-el2\qebspilaa64.efi): noproxy  test build without the UEFI proxy vote (QEBSPIL_NO_PROXY_VOTE=1) proxy    the normal |
| [`quiet-lines-test.sh`](quiet-lines-test.sh) | On "test: el2-drips", after spss-stop-test.sh: are the always-asserted (disabled) interrupt lines what makes TrustZone return from DRIPS at once? |
| [`rpmh-read-test.sh`](rpmh-read-test.sh) | On "test: pdc" (rebuilt with rpmh_read): read back every cmd-db resource on Linux's RPMh channel (APSS DRV 2), once as booted and once after releasing the boot  |
| [`rpmh-sleepset.sh`](rpmh-sleepset.sh) | What does Linux leave voted at RPMh while asleep? |
| [`rpmh-trace-prep.sh`](rpmh-trace-prep.sh) | GRUB test entry "ufsfix-trace": like "ufsfix" (DRIPS DTB, no clk/pd flags, pcie_port_pm=force, patched ufs-qcom initramfs) plus RPMh tracing from boot. |
| [`rsc-peek.sh`](rsc-peek.sh) | Read (never write) what each apps RSC channel has programmed: drv-2 (Linux, as a check), then drv-1 and drv-0 (hypervisor / TrustZone). |
| [`rscc-dump.sh`](rscc-dump.sh) | Did UEFI leave RPMh votes in the display RSC (DRV 9), which Linux never uses? |
| [`setup-el2.sh`](setup-el2.sh) | Prepare the EL2 test boot. |
| [`sleep-test.sh`](sleep-test.sh) | On "test: sleep" (7.2.7-book4s): load the EL1 timer module and the ADSP Modern Standby notifier, check the new kernel's pieces, then one probe suspend (wake it  |
| [`sleepstate-prep.sh`](sleepstate-prep.sh) | DSP "sleepstate" SMP2P entries (Windows qcsubsys behaviour): rebuild the sleep kernel's modules (adds book4_dsp_sleepstate) and the EL2 DTB of "test: el2-sleep" |
| [`spss-check.sh`](spss-check.sh) | Is the Secure Processor (SPSS) running and does it ever sleep? |
| [`spss-stop-test.sh`](spss-stop-test.sh) | Does the Secure Processor (SPSS, started by UEFI, unattended under Linux) block deep sleep? |
| [`timer-test.sh`](timer-test.sh) | On the "test: el2-drips" boot: are leftover EL1 timers pending at EL2? |
| [`ufs-refclk-check.sh`](ufs-refclk-check.sh) | Does UFS leak enables on its ref_clk (RPMh clk8, an XO buffer)? |
| [`ufsfix-prep.sh`](ufsfix-prep.sh) | Prepare the UFS ref_clk leak fix test (16 October): 1. |
| [`usb-rpm-test.sh`](usb-rpm-test.sh) | The USB controllers never runtime-suspend (power/control = on), so their genpd performance vote (CX NOMINAL) stays in force through system suspend and CX can ne |
| [`vreg-off-test.sh`](vreg-off-test.sh) | Regulators no Linux driver uses stay at UEFI's last RPMh vote ("unknown" state; regulator_late_cleanup skips them). |
| [`wifi-linkdown-test.sh`](wifi-linkdown-test.sh) | Awake test, no suspend: take the Wi-Fi link fully down (remove the card, Link Disable on the root port) and bring it back through the hotplug slot. |
| [`wifi-remove-test.sh`](wifi-remove-test.sh) | Awake test: can the Wi-Fi card be removed from PCI and brought back without the old panic (docs/firmware.md: ath12k_qmi_phy_cap_send)? |
