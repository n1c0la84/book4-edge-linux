# Device trees

Compiled and padded (`dtc -p 8192`), ready for GRUB's `devicetree` command.

| file | source | status |
|---|---|---|
| `x1e80100-samsung-galaxy-book4-edge-14.anatase.dtb` | Anatase `anatase-7.2` sources, built against their 7.2 `hamoa.dtsi` | **default**; needs `samsung-emuec` for the display |
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
