@echo -off
# Book4 Edge EL2 boot from the internal ESP (install/el2/esp-install.sh).
# Firmware boot entry "Book4 EL2 (slbounce)" starts this UEFI Shell from
# \EFI\book4-el2\, which runs this script: load qebspil (starts the ADSP and
# CDSP at ExitBootServices when the DTB marks them qcom,broken-reset, i.e.
# only for EL2 DTBs), load slbounce (Secure-Launch to EL2 at
# ExitBootServices, only for a DTB with the GPU zap shader disabled), then
# Fedora's GRUB. Normal (EL1) GRUB entries boot as usual from here too.
for %i run (0 63)
  if exist fs%i:\EFI\book4-el2\qebspilaa64.efi then
    set esp fs%i
    goto ESP
  endif
endfor
echo "book4-el2: \EFI\book4-el2\qebspilaa64.efi not found on fs0-fs63"
goto END
:ESP
%esp%:
load %esp%:\EFI\book4-el2\qebspilaa64.efi
load %esp%:\EFI\book4-el2\slbounce.efi
%esp%:\EFI\fedora\grubaa64.efi
:END
