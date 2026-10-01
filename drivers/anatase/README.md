# Anatase drivers (third-party)

**Author:** Antheas Kapenekakis <lkml@antheas.dev>
**Origin:** https://github.com/anatase-org/patchwork, branch `anatase-7.2`
(retrieved 30 September 2026).
**Licence:** GPL-2.0-only (see the SPDX headers).

The two `.c` files here are **unmodified** copies. `Makefile` and `dkms.conf`
are ours, for building them out of tree against a distribution kernel.

Our changes are kept as separate patches in `patches/`, applied at install
time, so the originals stay identifiable and the patches can be sent upstream:

- `0001-samsung-emuec-retry-PD-request-after-hot-plug.patch`
