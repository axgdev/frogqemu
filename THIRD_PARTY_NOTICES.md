<!-- SPDX-License-Identifier: MIT -->

# Third-Party Notices

This repository does not vendor QEMU source. `make fetch` downloads QEMU
10.2.2 from `https://download.qemu.org/` into `.cache/`, which is ignored by
git. QEMU is Copyright Fabrice Bellard and the QEMU contributors and is
licensed as described by QEMU's own `LICENSE`, `COPYING`, and per-file SPDX
headers. The SF2000 machine patch in this repository is GPL-2.0-or-later so it
can be applied to and built with QEMU.

The generated QEMU binary is a GPL-covered QEMU build. If you distribute that
binary, distribute the corresponding source, including the exact QEMU source
version and these local SF2000 patches.

Firmware blobs and stock OS files are inputs for research and are not included
or relicensed by this repository:

- `SF2000_XMC_XM25QH40B_4mbit.bin`
- `SF2000_XMC_XM25QH40B_4mbit_bugfix.bin`
- `bisrv_08_03.asd`
- Datafrog SF2000 vanilla OS files downloaded by `make vanilla-sd`

Keep those artifacts outside git unless their license permits redistribution.
Generated SD-card images and video/screenshot captures are written under
`build/`, which is ignored by git.

Host tools used by optional targets include `ffmpeg`, ImageMagick, `mtools`,
`dosfstools`, and `unzip`; they are not bundled by this repository.
