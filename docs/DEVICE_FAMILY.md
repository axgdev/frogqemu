# SF2000 Family Device Notes

<!-- SPDX-License-Identifier: MIT -->

The SF2000, GB300, DY-series, Q19, E2, X60, and related boards appear to share
the HC15xx/SF2000 SoC family while varying the LCD panel, local controls,
wireless receiver population, USB host use, audio routing, and shell-specific
button layout. QEMU should model the common SoC first, then make the board
differences explicit so the same emulator can validate a future universal open
driver stack.

## Panel Capture Sources

Panel register captures live outside this repository in:

```text
/root/host-frogdev/universal/devices/lcd_reg_*.txt
```

Treat those files as readback observations, not as ready-to-run init sequences.
Some capture scripts print command and response bytes in a way that can look
like reversed command ordering. Do not turn an observed row into a write
sequence without confirming it against firmware code or a direct hardware
probe.

Known panel identity groups from the captures:

| Device capture | `0x04` manufacturer ID | `0xd3` ID | `0xda/0xdb/0xdc` | Notes |
| --- | --- | --- | --- | --- |
| `lcd_reg_GB300.txt` | `00 00 93 06` | `00 00 93 06` | `00/93/06` | Same signature as AN66. UniFrog treats `0x009306` as GB300-family input/audio routing. |
| `lcd_reg_AN66.txt` | `00 00 93 06` | `00 00 93 06` | `00/93/06` | Same LCD identity as GB300 in this probe set. |
| `lcd_reg_DY14.txt` | `00 00 93 07` | `00 00 93 07` | `00/93/07` | UniFrog treats `0x009307` like GB300 for some board routing. |
| `lcd_reg_SF2000_turquoise.txt` | `e4 3e 81 f5` | `f3 f3 f3 f3` | `fa/fb/fc` with payload `3e/81/f5` | SF2000 variant with a distinct ID payload. |
| `lcd_reg_SF2000_28G105.txt` | `e4 85 85 52` | `f3 f3 f3 f3` | `fa/fb/fc` with payload `85/85/52` | Older SF2000-compatible capture pattern. |
| `lcd_reg_DY12_MY2024.txt` | `a4 85 85 52` | `b3 00 00 00` | `ba/bb/bc` with payload `85/85/52` | Newer DY12-style capture. |
| `lcd_reg_DY19_new.txt` | `a4 85 85 52` | `b3 00 00 00` | `ba/bb/bc` with payload `85/85/52` | Similar to DY12 MY2024, with a different `0xf2` option byte. |
| `lcd_reg_Q19_new.txt` | `a4 85 85 52` | `b3 00 00 00` | `ba/bb/bc` with payload `85/85/52` | Similar to DY12 MY2024. |
| `lcd_reg_E2.txt` | `e4 85 85 52` | `f3 00 00 00` | `fa/fb/fc` with payload `85/85/52` | Same payload as 28G105 with different echoed command bytes. |
| `lcd_reg_Q19.txt` | `61 61 bc 11` | `00 61 bc 11` | `61/bc/11` | Distinct Q19 capture with useful `0xf2`/`0xf6` readbacks. |
| `lcd_reg_X60_my.txt` | `00 e3 00 00` | `00 00 93 29` | `00/e3/00` | Distinct panel timing/control readbacks. |
| `lcd_reg_DY12.txt` | mostly echoed command bytes | `b3 b3 b3 b3` | `00/00/00` | Likely an older or less informative readback path. |

## QEMU Board Modeling Plan

Keep the default `sf2000` machine compatible with the stock SF2000 08.03 image
until a board selector is needed. The next modelable board differences are:

- Panel read IDs: implement the GPIO-8080 read direction and return board
  profile responses for `0x04`, `0x09`, `0x0a`, `0x0c`, `0xd3`,
  `0xda`, `0xdb`, and `0xdc`.
- Panel geometry and transform: preserve the common 320x240 framebuffer path,
  but make MADCTL and set-address-window behavior visible enough to catch
  rotated or mirrored init mistakes.
- Input matrix: keep local L23/L24 shift-register scanning separate from the
  GPIO-bitbanged RF bus on L27/L28/L29. GB300-family USB gamepad support should
  be modeled as a separate USB host path, not mixed into the RF receiver.
- Audio and amplifier routing: UniFrog already uses LCD ID clues for board
  routing. QEMU should move toward an explicit board profile once those routes
  are validated.
- Firmware images: SF2000 stock uses
  `/root/host-frogdev/universal/orig_firmware/bisrv_08_03.asd`; GB300 stock
  firmware is available at
  `/root/host-frogdev/universal/sf2000_gb300_multicore_private/bisrv_gb300_v2.asd`.
  The private symbol script maps both SF2000 and GB300 firmware addresses:
  `/root/host-frogdev/universal/sf2000_gb300_multicore_private/scripts/firmware-symbol.py`.

The immediate emulator goal is not to make every board boot by special casing
firmware quirks. It is to make common SoC behavior accurate, expose board
differences as data, and use stock firmware plus UniFrog probes to converge on
drivers that can run unchanged across the family.
