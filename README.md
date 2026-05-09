# SF2000 QEMU Bring-Up

This project carries a small, patch-based QEMU board model for the Data Frog
SF2000 / HC15xx family. The goal is fast firmware bring-up and hardware
contract discovery, not a complete emulator yet.

The baseline is QEMU 10.2.2. It is a conservative stable baseline with modern
MIPS TCG, VNC, and GDB stub support, without chasing brand-new 11.x churn while
the board model is still experimental. Moving the patch forward should stay
small because the SF2000 code is isolated in `hw/mips/sf2000.c`.

## Install Host Dependencies

On Alpine:

```sh
apk add --no-cache curl meson ninja patch pkgconf glib-dev pixman-dev py3-pip py3-distlib
```

The debug target expects the project toolchain GDB at:

```sh
/opt/gdb-mips-toolchain/bin/mipsel-mti-elf-gdb
```

Override with `GDB=/path/to/mipsel-gdb` if needed.

## Build

```sh
make build
make smoke
```

`make build` downloads QEMU 10.2.2 into `.cache/`, applies the local patch,
configures only `mipsel-softmmu`, and builds `qemu-system-mipsel`.

The default firmware path is:

```sh
/root/host-frogdev/universal/orig_firmware/SF2000_XMC_XM25QH40B_4mbit.bin
```

Override it with:

```sh
make smoke FIRMWARE=/path/to/firmware.bin
```

The stock ASD path defaults to:

```sh
/root/host-frogdev/universal/orig_firmware/bisrv_08_03.asd
```

Run the current direct stock ASD bring-up smoke with:

```sh
make smoke-stock-bootloader
make smoke-stock-full
make smoke-stock-asd
make smoke-stock-fatfs
make smoke-stock-display
```

`make smoke-stock-bootloader` starts the stock bootloader body from the flash
partition recorded in the image `HEAD` table (`0x5c00`) and verifies that the
bootloader reaches UART output and SD initialization. The direct reset-vector
path still needs the vendor cache trampoline modelled before it can run without
this helper entry.

`make smoke-stock-full` builds `build/sf2000-stock.sd.img`, a tiny FAT image
containing `/BIOS/bisrv.asd`, then boots the stock bootloader against that raw
image. This is the current full-chain diagnostic target. It proves block-backed
SD reads from the bootloader path. The generated image uses a small FAT16
layout because that matches the stock bootloader path better than the earlier
FAT32 probe. The target currently accepts the bootloader finding `BISRV.ASD`;
the next blocker is the follow-up close/read path tripping the bootloader's
exception handler after the first file-sector read.

`make smoke-stock-fatfs` boots the stock ASD far enough to exercise the SDIO
DMA read path and confirm that the stock firmware reaches its FatFs mount
success message.

`make smoke-stock-display` checks that the stock ASD reaches the HC16xx GMA
scanout path and emits both the CLUT8 splash/menu descriptor and later RGB565
framebuffer descriptor. The emulator currently bridges the ST7789 panel init
sequence to QEMU display output by decoding those GMA descriptor writes.

## Run With VNC

```sh
make run-vnc
```

By default this listens on `127.0.0.1:5901` because QEMU VNC display `:1`
maps to TCP port 5901. For a headless homelab, expose a chosen interface:

```sh
make run-vnc VNC=0.0.0.0:1
```

Then connect GNOME Connections to:

```text
vnc://host:5901
```

Logs are written to `build/logs/sf2000.log`.

Without `SD_IMAGE`, the SD controller serves a tiny synthetic FAT32-like probe
card that is enough for the stock firmware to mount in direct ASD mode. To
attach a real raw SD image, QEMU uses an unconnected block backend named `sd0`
because this machine model owns the controller directly rather than exposing a
generic QEMU SD bus:

```sh
make run-vnc SD_IMAGE=/path/to/sd.img
make boot-stock-asd SD_IMAGE=/path/to/sd.img
```

## Debug

Start QEMU paused with a GDB stub:

```sh
make debug
```

In another shell:

```sh
make gdb
```

Useful early commands:

```gdb
x/16i 0xbfc00000
info registers
si
```

## Current Emulation Scope

Implemented:

- MIPS little-endian `24Kc` CPU model with a 396 MHz reference clock.
- 128 MiB RAM at physical `0x00000000`.
- Boot flash image at physical `0x1fc00000`, matching the MIPS reset alias at
  virtual `0xbfc00000`.
- Direct ASD bring-up mode through `-kernel`, loaded at physical `0x00000000`
  with entry `0x80001000`.
- Permissive MMIO logging from `0x10000000` to before the boot flash window.
- A minimal RGB565 framebuffer console block at `0x18000000`.
- Early system register defaults for chip ID, clocks, pinmux, and PLL probing.
- A minimal timer/interrupt path sufficient for the stock ASD scheduler loop.
- UART line capture to the QEMU log.
- A minimal SDIO command and DMA read path, backed by either a raw `IF_SD`
  image named `sd0` or a synthetic FAT probe card.
- A host-side `tools/mksf2000sd.c` helper that creates a tiny raw FAT image
  with `/BIOS/bisrv.asd` for bootloader diagnostics.

Not implemented yet:

- A complete HC15xx display controller and panel model.
- GPIO keys, audio, SPI/NAND layout, writes to SD media, and full controller
  timing semantics.
- ASD package loading.

The first practical milestone is to run stock firmware far enough to collect
unknown MMIO accesses and map them back to the real SF2000 drivers.

See [docs/SF2000.md](docs/SF2000.md) for the boot-chain and address-map details
that are easy to get wrong.
