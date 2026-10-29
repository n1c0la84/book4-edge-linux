@echo -off
# Book4 Edge EL2 boot from the internal ESP, for a system installed from the
# live ISO (install/arch/book4-install.sh, no Fedora): GRUB \EFI\book4\
# chainloads this UEFI Shell; load qebspil and slbounce, then the second GRUB
# \EFI\book4\grub-el2.efi, which boots the EL2 entry.
for %i run (0 63)
  if exist fs%i:\EFI\book4\grub-el2.efi then
    set esp fs%i
    goto ESP
  endif
endfor
echo "book4: \EFI\book4\grub-el2.efi not found on fs0-fs63"
goto END
:ESP
%esp%:
load %esp%:\EFI\book4-el2\qebspilaa64.efi
load %esp%:\EFI\book4-el2\slbounce.efi
%esp%:\EFI\book4\grub-el2.efi
:END
