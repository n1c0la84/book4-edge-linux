# Device trees

> **Current state (26 November 2026):** On `linux-book4` 7.3 (`book4/7.3`), the
> 14" DTB is compiled directly by the kernel package
> (`packages/linux-book4/PKGBUILD`), and the **only active file here is
> `src/x1-el2-book4.dtso`** (packaged in `book4-edge-boot` and applied onto the
> kernel's DTB by `book4-boot`). The precompiled `.dtb` binaries, `patches/`
> (`0001`–`0006`), and other `src/*.dts*` files are 7.2-era history kept for
> reference.

Compiled and padded (`dtc -p 8192`), ready for GRUB's `devicetree` command (7.2 era):

| file | source | status |
|---|---|---|
| `x1e80100-samsung-galaxy-book4-edge-14.anatase.dtb` | Anatase `anatase-7.2` sources, built against their 7.2 `hamoa.dtsi` | legacy 7.2 default; needs `samsung-emuec` for the display |
| `x1e80100-samsung-galaxy-book4-edge-14.book4-own.dtb` | linux-arm-msm v6 series rebased on 7.2.6 `hamoa.dtsi` | fallback; works with `drivers/book4-ec` |

To flip one property without the kernel tree:

    dtc -I dtb -O dts in.dtb > x.dts   # edit
    dtc -I dts -O dtb -p 8192 -o out.dtb x.dts

`patches/` apply in order on Anatase `anatase-7.2` (`2ad788424`): 0001-0002
the camera, 0003 the tweeters. 0003 was first made on the bare base and sent
to Anatase in that form (kernel-anatase#4); the copy here is rebased onto
0002 (same changes, both add blocks at the end of the -14.dts), made with
`tools/kernel/merge-dts-patches.sh` on 6 October and checked by compiling
the DTB. `install/kernel-branch.sh` turns them into the `book4/7.2` branch.
