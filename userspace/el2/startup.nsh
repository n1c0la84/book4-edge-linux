@echo -off
# Galaxy Book4 Edge EL2 boot (book4-edge-el2 package; installed into
# \EFI\book4-el2-arch\ by `book4-el2 install`). Firmware entry "Omarchy (EL2,
# Arch GRUB)" starts this UEFI Shell, which runs this script: load qebspil
# (starts the ADSP and CDSP at ExitBootServices when the DTB marks them
# qcom,broken-reset, i.e. only for EL2 DTBs; firmware from \firmware\),
# load slbounce (Secure-Launch to EL2 at ExitBootServices, only for a DTB
# with the GPU zap shader disabled; tcblaunch.exe from this folder), then
# Arch GRUB, and Fedora's GRUB if Arch's is missing or returns. EL1 entries
# boot as usual from here too. The loop finds the ESP with both files: a
# live stick plugged in can be mapped first.
for %i run (0 63)
  if exist fs%i:\EFI\arch\grubaa64.efi then
    if exist fs%i:\EFI\book4-el2-arch\qebspilaa64.efi then
      set esp fs%i
      goto ESP
    endif
  endif
endfor
echo "book4-el2: no fs0-fs63 has both \EFI\book4-el2-arch\qebspilaa64.efi and \EFI\arch\grubaa64.efi"
goto END
:ESP
%esp%:
load %esp%:\EFI\book4-el2-arch\qebspilaa64.efi
load %esp%:\EFI\book4-el2-arch\slbounce.efi
%esp%:\EFI\arch\grubaa64.efi
# Arch GRUB missing or returned: Fedora's GRUB, the same menu as before part B.
if exist %esp%:\EFI\fedora\grubaa64.efi then
  %esp%:\EFI\fedora\grubaa64.efi
endif
:END
