@echo -off
# Book4 Edge live stick, EL2 path (install/arch/live-image.sh). The stick's
# GRUB chainloads this UEFI Shell from \EFI\book4-el2\ on the stick: load
# qebspil (starts the ADSP and CDSP at ExitBootServices for an EL2 DTB) and
# slbounce (Secure-Launch to EL2), then the stick's second GRUB, which boots
# the EL2 entry. Found by the marker file, not by path: the internal ESP has
# its own \EFI\book4-el2\.
for %i run (0 63)
  if exist fs%i:\book4-live.id then
    set stick fs%i
    goto STICK
  endif
endfor
echo "book4-live: \book4-live.id not found on fs0-fs63"
goto END
:STICK
%stick%:
load %stick%:\EFI\book4-el2\qebspilaa64.efi
load %stick%:\EFI\book4-el2\slbounce.efi
%stick%:\EFI\book4-live\grub-el2.efi
:END
