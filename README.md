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
make smoke-stock-asd
```

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

Not implemented yet:

- Real HC15xx display controller registers.
- Timers, interrupt controller, GPIO, keys, SD controller, SPI/NAND layout, and
  audio.
- ASD package loading.

The first practical milestone is to run stock firmware far enough to collect
unknown MMIO accesses and map them back to the real SF2000 drivers.

See [docs/SF2000.md](docs/SF2000.md) for the boot-chain and address-map details
that are easy to get wrong.
