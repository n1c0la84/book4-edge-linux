@echo -off
# EL2 boot via slbounce, from this USB stick: load slbounce (it uses
# \tcblaunch.exe from this stick), then start Fedora's GRUB from the
# internal ESP. Only a GRUB entry whose DTB disables the GPU zap shader
# ("... - test: el2") switches to EL2; every other entry boots as usual.
for %i run (0 63)
  if exist fs%i:\slbounce.efi then
    set stick fs%i
    goto STICK
  endif
endfor
echo "slbounce.efi not found on any filesystem"
goto END
:STICK
for %j run (0 63)
  if exist fs%j:\EFI\fedora\grubaa64.efi then
    set esp fs%j
    goto ESP
  endif
endfor
echo "Fedora GRUB (\EFI\fedora\grubaa64.efi) not found on fs0-fs63; filesystems:"
map -t fs
goto END
:ESP
echo " "
echo "=== Galaxy Book4 Edge: EL2 boot via slbounce ==="
echo "stick: %stick%   internal ESP: %esp%"
echo "Next: load slbounce, then GRUB. In GRUB pick 'Arch Linux (...) - test: el2'."
echo "Any other entry boots normally (EL1). 'q' stops here (sltest stays usable)."
pause
%stick%:
load %stick%:\slbounce.efi
%esp%:\EFI\fedora\grubaa64.efi
:END
