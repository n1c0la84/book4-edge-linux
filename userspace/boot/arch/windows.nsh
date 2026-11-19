@echo -off
# Start Windows' boot manager from the UEFI Shell (book4-edge-linux,
# userspace/boot/arch/windows.nsh, in \EFI\book4-el2-arch\). Arch GRUB 2.16
# cannot chainload bootmgfw.efi on this disk (BCD 0xc00000bb, 19 November);
# its "Windows Boot Manager" entry chainloads the Shell with this script,
# and the Shell loads bootmgfw.efi with the firmware's own device path, as
# the firmware boot menu does.
for %i run (0 63)
  if exist fs%i:\EFI\Microsoft\Boot\bootmgfw.efi then
    fs%i:\EFI\Microsoft\Boot\bootmgfw.efi
    goto END
  endif
endfor
echo "windows.nsh: no fs0-fs63 has \EFI\Microsoft\Boot\bootmgfw.efi"
:END
