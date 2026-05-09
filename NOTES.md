# Bring-Up Notes

## Why QEMU

QEMU gives the best path to running stock firmware because it already has MIPS
TCG, remote GDB, VNC, monitor commands, and a maintainable device model API.
Unicorn is useful for narrow CPU-only traces, but it does not provide the full
machine framework needed to boot firmware with display, storage, timers, and
interrupts.

## Firmware Inputs

Known local firmware files:

```text
/root/host-frogdev/universal/orig_firmware/SF2000_XMC_XM25QH40B_4mbit.bin
/root/host-frogdev/universal/orig_firmware/UpdateFirmware/SF2000_XMC_XM25QH40B_4mbit_bugfix.bin
/root/host-frogdev/universal/orig_firmware/bisrv_08_03.asd
```

The current machine consumes the SPI boot image through `-bios` and can inject
the stock ASD directly with `-kernel` for faster bring-up. SD reads use an
unconnected QEMU block backend named `sd0` when `SD_IMAGE=/path/to/sd.img` is
passed through the Makefile, otherwise the board serves a synthetic FAT probe
card.

`tools/mksf2000sd.c` creates `build/sf2000-stock.sd.img` for the full-chain
bootloader diagnostic. That image contains `/BIOS/bisrv.asd`; the bootloader
currently reads the attached image's MBR and volume sector but does not yet
walk into the generated FAT directory sectors.

## Reverse Engineering Loop

1. Run with `make debug`.
2. Connect with `make gdb`.
3. Let firmware execute until it hits unknown MMIO.
4. Inspect `build/logs/sf2000.log`.
5. Add a small device stub for the observed register block.
6. Repeat.

Keep stubs permissive at first: return stable values and log writes. Tighten
behavior only when the firmware needs it.
