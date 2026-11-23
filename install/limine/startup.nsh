@echo -off
# Galaxy Book4 Edge EL2 boot through Limine (docs/plan-limine.md step 3;
# installed into \EFI\book4-el2-limine\ on the firmware ESP by
# install/arch/limine-test.sh). Firmware entry "Omarchy (EL2, Limine)" starts
# this UEFI Shell, which runs this script: load qebspil and slbounce from the
# EL2 chain's folder (as \EFI\book4-el2-arch\startup.nsh does), then start
# Limine from the second ESP (BOOK4ESP, /boot: \EFI\limine\BOOTAA64.EFI and
# \limine.conf). If Limine is missing or returns: Arch GRUB, as the normal
# EL2 entry would.
for %i run (0 63)
  if exist fs%i:\EFI\book4-el2-arch\qebspilaa64.efi then
    if exist fs%i:\EFI\arch\grubaa64.efi then
      set esp fs%i
      goto ESP
    endif
  endif
endfor
echo "book4-el2-limine: no fs0-fs63 has \EFI\book4-el2-arch\qebspilaa64.efi and \EFI\arch\grubaa64.efi"
goto END
:ESP
%esp%:
load %esp%:\EFI\book4-el2-arch\qebspilaa64.efi
load %esp%:\EFI\book4-el2-arch\slbounce.efi
for %j run (0 63)
  if exist fs%j:\EFI\limine\BOOTAA64.EFI then
    if exist fs%j:\limine.conf then
      set lim fs%j
      goto LIM
    endif
  endif
endfor
echo "book4-el2-limine: Limine (\EFI\limine\BOOTAA64.EFI with \limine.conf) not found; Arch GRUB instead"
goto GRUB
:LIM
%lim%:
%lim%:\EFI\limine\BOOTAA64.EFI
:GRUB
# Limine missing or returned: Arch GRUB (slbounce and qebspil stay loaded).
%esp%:
%esp%:\EFI\arch\grubaa64.efi
:END
