QEMU_VERSION := 10.2.2
QEMU_TARBALL := qemu-$(QEMU_VERSION).tar.xz
QEMU_URL := https://download.qemu.org/$(QEMU_TARBALL)
QEMU_SRC := .cache/qemu-$(QEMU_VERSION)
QEMU_BIN := $(QEMU_SRC)/build/qemu-system-mipsel
MKSD := build/mksf2000sd
STOCK_SD_IMAGE := build/sf2000-stock.sd.img
STOCK_SD_IMAGE_FAT16 := build/sf2000-stock-fat16.sd.img
VANILLA_URL := https://github.com/Dteyn/Datafrog_SF2000_Vanilla/releases/download/v1.6/DATAFROG-SF2000-08.03-OS-Files-Only-VANILLA.zip
VANILLA_ZIP := build/downloads/DATAFROG-SF2000-08.03-OS-Files-Only-VANILLA.zip
VANILLA_DIR := build/vanilla-os
VANILLA_SD_IMAGE := build/sf2000-vanilla.sd.img

FIRMWARE ?= /root/host-frogdev/universal/orig_firmware/SF2000_XMC_XM25QH40B_4mbit.bin
FIRMWARE_BUGFIX ?= /root/host-frogdev/universal/orig_firmware/UpdateFirmware/SF2000_XMC_XM25QH40B_4mbit_bugfix.bin
ASD ?= /root/host-frogdev/universal/orig_firmware/bisrv_08_03.asd
GDB ?= /opt/gdb-mips-toolchain/bin/mipsel-mti-elf-gdb
VNC ?= 127.0.0.1:1
LOG ?= build/logs/sf2000.log
CAPTURE_DELAY ?= 60
SCREENSHOT ?= build/screenshots/sf2000-stock-capture.ppm
GMA_DUMP_DIR ?= build/screenshots/gma
GMA_DUMP_LIMIT ?= 16
SD_IMAGE ?=
SD_ARGS = $(if $(SD_IMAGE),-drive if=none,id=sd0,file=$(SD_IMAGE),format=raw,)

.PHONY: all help deps fetch patch configure build vanilla-sd run-vnc run-headless boot-stock-asd debug capture-stock-ui capture-vanilla-ui smoke smoke-input smoke-stock-bootloader smoke-stock-full smoke-stock-full-bugfix smoke-stock-full-vanilla smoke-stock-full-fat16 smoke-stock-asd smoke-stock-fatfs smoke-stock-display clean distclean

all: build

help:
	@printf '%s\n' \
		'Targets:' \
		'  make deps          show required Alpine packages' \
		'  make build         fetch, patch, configure, and build QEMU' \
		'  make smoke         verify the sf2000 machine exists and firmware loads' \
		'  make smoke-input   verify HMP/VNC keyboard events reach the keypad' \
		'  make smoke-stock-bootloader verify stock bootloader reaches SD init' \
		'  make smoke-stock-full diagnose stock bootloader FAT32 /BIOS/bisrv.asd load' \
		'  make smoke-stock-full-bugfix verify fixed stock bootloader reaches firmware UI' \
		'  make smoke-stock-full-vanilla verify fixed bootloader mounts vanilla OS image' \
		'  make smoke-stock-full-fat16 run the same bootloader path on FAT16' \
		'  make smoke-stock-asd verify direct stock ASD boot reaches early MMIO' \
		'  make smoke-stock-fatfs verify stock ASD reaches SD/FatFs mount' \
		'  make smoke-stock-display verify stock ASD drives GMA scanout' \
		'  make run-vnc       run with VNC display, default 127.0.0.1:5901' \
		'  make run-vnc SD_IMAGE=/path/sd.img attach a raw SD-card image' \
		'  make capture-stock-ui write screendump and GMA frames to build/screenshots' \
		'  make capture-vanilla-ui download vanilla OS files and capture GMA frames' \
		'  make vanilla-sd    build a generated FAT32 image from the vanilla OS zip' \
		'  make boot-stock-asd run stock boot ROM plus direct stock ASD load' \
		'  make debug         run paused with GDB stub on :1234' \
		'  make gdb           connect mipsel-mti-elf-gdb to :1234' \
		'  make clean         remove QEMU build directory only' \
		'  make distclean     remove downloaded and generated artifacts'

deps:
	@printf '%s\n' \
		'apk add --no-cache curl meson ninja patch pkgconf glib-dev pixman-dev py3-pip py3-distlib' \
		'optional for vanilla-sd: apk add --no-cache dosfstools mtools unzip'

fetch: $(QEMU_SRC)/.fetched

$(QEMU_SRC)/.fetched:
	mkdir -p .cache
	test -f .cache/$(QEMU_TARBALL) || curl -L -o .cache/$(QEMU_TARBALL) $(QEMU_URL)
	rm -rf $(QEMU_SRC)
	mkdir -p $(QEMU_SRC)
	tar -xf .cache/$(QEMU_TARBALL) -C $(QEMU_SRC) --strip-components=1
	touch $@

patch: $(QEMU_SRC)/.patched

$(QEMU_SRC)/.patched: $(QEMU_SRC)/.fetched patches/qemu-$(QEMU_VERSION)/0001-hw-mips-add-sf2000-machine.patch
	cd $(QEMU_SRC) && { test -f hw/mips/sf2000.c || patch -p1 < ../../patches/qemu-$(QEMU_VERSION)/0001-hw-mips-add-sf2000-machine.patch; }
	touch $@

configure: $(QEMU_SRC)/build/build.ninja

$(QEMU_SRC)/build/build.ninja: $(QEMU_SRC)/.patched
	cd $(QEMU_SRC) && ./configure \
		--target-list=mipsel-softmmu \
		--disable-docs \
		--disable-gtk \
		--disable-sdl \
		--disable-opengl \
		--disable-virglrenderer \
		--disable-vte \
		--disable-curses \
		--enable-vnc \
		--disable-werror

build: $(QEMU_BIN)

$(QEMU_BIN): $(QEMU_SRC)/build/build.ninja
	ninja -C $(QEMU_SRC)/build qemu-system-mipsel

$(MKSD): tools/mksf2000sd.c
	mkdir -p $(dir $@)
	$(CC) -O2 -Wall -Wextra -o $@ $<

$(STOCK_SD_IMAGE): $(MKSD) $(ASD)
	$(MKSD) $(ASD) $@ fat32

$(STOCK_SD_IMAGE_FAT16): $(MKSD) $(ASD)
	$(MKSD) $(ASD) $@ fat16

$(VANILLA_ZIP):
	mkdir -p $(dir $@)
	curl -L -o $@ $(VANILLA_URL)

$(VANILLA_DIR)/.extracted: $(VANILLA_ZIP)
	rm -rf $(VANILLA_DIR)
	mkdir -p $(VANILLA_DIR)
	unzip -q $(VANILLA_ZIP) -d $(VANILLA_DIR)
	touch $@

$(VANILLA_SD_IMAGE): $(VANILLA_DIR)/.extracted
	command -v mcopy >/dev/null
	command -v mkfs.vfat >/dev/null
	rm -f $@
	truncate -s 256M $@
	mkfs.vfat -n SF2000 $@
	mcopy -i $@ -s $(VANILLA_DIR)/* ::

vanilla-sd: $(VANILLA_SD_IMAGE)

run-vnc: build
	mkdir -p $(dir $(LOG))
	$(QEMU_BIN) -M sf2000 -bios $(FIRMWARE) $(SD_ARGS) \
		-display vnc=$(VNC) \
		-serial none -monitor stdio \
		-d guest_errors,unimp -D $(LOG)

run-headless: build
	mkdir -p $(dir $(LOG))
	$(QEMU_BIN) -M sf2000 -bios $(FIRMWARE) $(SD_ARGS) \
		-display none -serial none -monitor stdio \
		-d guest_errors,unimp -D $(LOG)

boot-stock-asd: build
	mkdir -p $(dir $(LOG))
	$(QEMU_BIN) -M sf2000 -bios $(FIRMWARE) -kernel $(ASD) $(SD_ARGS) \
		-display vnc=$(VNC) \
		-serial none -monitor stdio \
		-d guest_errors,unimp -D $(LOG)

capture-stock-ui: build $(STOCK_SD_IMAGE)
	mkdir -p $(dir $(LOG)) $(dir $(SCREENSHOT)) $(GMA_DUMP_DIR)
	(sleep $(CAPTURE_DELAY); printf 'screendump %s\n' '$(SCREENSHOT)'; \
		sleep 1; printf 'quit\n') | \
		SF2000_GMA_DUMP_DIR=$(GMA_DUMP_DIR) \
		SF2000_GMA_DUMP_LIMIT=$(GMA_DUMP_LIMIT) \
		$(QEMU_BIN) -M sf2000 -bios $(FIRMWARE_BUGFIX) \
		-drive if=none,id=sd0,file=$(STOCK_SD_IMAGE),format=raw \
		-display none -serial none -monitor stdio \
		-d guest_errors,unimp -D $(LOG) \
		> build/logs/capture-stock-ui.console 2>&1
	@printf 'wrote %s\n' '$(SCREENSHOT)'
	@find $(GMA_DUMP_DIR) -maxdepth 1 -type f -name 'sf2000-gma-*.ppm' -print | sort | tail -5

capture-vanilla-ui: build $(VANILLA_SD_IMAGE)
	mkdir -p $(dir $(LOG)) $(dir $(SCREENSHOT)) $(GMA_DUMP_DIR)
	(sleep $(CAPTURE_DELAY); printf 'screendump %s\n' '$(SCREENSHOT)'; \
		sleep 1; printf 'quit\n') | \
		SF2000_GMA_DUMP_DIR=$(GMA_DUMP_DIR) \
		SF2000_GMA_DUMP_LIMIT=$(GMA_DUMP_LIMIT) \
		$(QEMU_BIN) -M sf2000 -bios $(FIRMWARE_BUGFIX) \
		-drive if=none,id=sd0,file=$(VANILLA_SD_IMAGE),format=raw \
		-display none -serial none -monitor stdio \
		-d guest_errors,unimp -D $(LOG) \
		> build/logs/capture-vanilla-ui.console 2>&1
	@printf 'wrote %s\n' '$(SCREENSHOT)'
	@find $(GMA_DUMP_DIR) -maxdepth 1 -type f -name 'sf2000-gma-*.ppm' -print | sort | tail -5

debug: build
	mkdir -p $(dir $(LOG))
	$(QEMU_BIN) -M sf2000 -bios $(FIRMWARE) -kernel $(ASD) $(SD_ARGS) \
		-display vnc=$(VNC) \
		-serial none -monitor stdio \
		-S -s -d in_asm,cpu,guest_errors,unimp -D $(LOG)

gdb:
	$(GDB) -ex 'set architecture mips' -ex 'set endian little' -ex 'target remote :1234'

smoke: build
	mkdir -p build/logs
	$(QEMU_BIN) -machine help | grep -q '^sf2000'
	timeout 2s $(QEMU_BIN) -M sf2000 -bios $(FIRMWARE) \
		-display none -serial none -monitor none \
		-d guest_errors,unimp -D build/logs/smoke.log \
		> build/logs/smoke.console 2>&1 || test $$? -eq 124
	grep -q 'sf2000: loaded' build/logs/smoke.console

smoke-input: build
	mkdir -p build/logs
	(sleep 1; printf 'sendkey right\n'; sleep 1; \
		printf 'sendkey x\n'; sleep 1; printf 'quit\n') | \
		$(QEMU_BIN) -M sf2000 -bios $(FIRMWARE) \
		-display none -serial none -monitor stdio \
		-d guest_errors,unimp -D build/logs/smoke-input.log \
		> build/logs/smoke-input.console 2>&1
	grep -q 'sf2000: key qcode=right down=1' build/logs/smoke-input.log
	grep -q 'sf2000: key qcode=x down=1' build/logs/smoke-input.log

smoke-stock-bootloader: build
	mkdir -p build/logs
	timeout 15s $(QEMU_BIN) -M sf2000 -bios $(FIRMWARE) \
		-display none -serial none -monitor none \
		-d guest_errors,unimp -D build/logs/smoke-stock-bootloader.log \
		> build/logs/smoke-stock-bootloader.console 2>&1 || test $$? -eq 124
	grep -q 'mirrored bootloader .*flash+0x00005c00' build/logs/smoke-stock-bootloader.console
	grep -q 'uart:  Hichip Bootloader' build/logs/smoke-stock-bootloader.log
	grep -q 'uart: \[INFO\].SD init cost' build/logs/smoke-stock-bootloader.log

smoke-stock-full: build $(STOCK_SD_IMAGE)
	mkdir -p build/logs
	timeout 45s $(QEMU_BIN) -M sf2000 -bios $(FIRMWARE) \
		-drive if=none,id=sd0,file=$(STOCK_SD_IMAGE),format=raw \
		-display none -serial none -monitor none \
		-d guest_errors,unimp -D build/logs/smoke-stock-full.log \
		> build/logs/smoke-stock-full.console 2>&1 || test $$? -eq 124
	grep -q 'uart:  Hichip Bootloader' build/logs/smoke-stock-full.log
	grep -q 'uart: \[INFO\].SD init cost' build/logs/smoke-stock-full.log
	grep -Eq 'uart: \[FS\]successed!|gma-present|uart: \[INFO\].----A BISRV.ASD|uart: \[ERR\].No Upgrade file -- 0:BIOS/bisrv.asd' build/logs/smoke-stock-full.log

smoke-stock-full-bugfix: build $(STOCK_SD_IMAGE)
	mkdir -p build/logs
	timeout 60s $(QEMU_BIN) -M sf2000 -bios $(FIRMWARE_BUGFIX) \
		-drive if=none,id=sd0,file=$(STOCK_SD_IMAGE),format=raw \
		-display none -serial none -monitor none \
		-d guest_errors,unimp -D build/logs/smoke-stock-full-bugfix.log \
		> build/logs/smoke-stock-full-bugfix.console 2>&1 || test $$? -eq 124
	grep -q 'uart:  Hichip Bootloader' build/logs/smoke-stock-full-bugfix.log
	grep -q 'uart: \[INFO\].CRC check pass !' build/logs/smoke-stock-full-bugfix.log
	grep -q 'gma-present .*mode=12' build/logs/smoke-stock-full-bugfix.log
	grep -q 'gma-present .*mode=6' build/logs/smoke-stock-full-bugfix.log
	grep -q 'uart: \[FS\]mount: /dev/sda1 -> /mnt/sda1' build/logs/smoke-stock-full-bugfix.log

smoke-stock-full-vanilla: build $(VANILLA_SD_IMAGE)
	mkdir -p build/logs
	timeout 150s $(QEMU_BIN) -M sf2000 -bios $(FIRMWARE_BUGFIX) \
		-drive if=none,id=sd0,file=$(VANILLA_SD_IMAGE),format=raw \
		-display none -serial none -monitor none \
		-d guest_errors,unimp -D build/logs/smoke-stock-full-vanilla.log \
		> build/logs/smoke-stock-full-vanilla.console 2>&1 || test $$? -eq 124
	grep -q 'uart:  Hichip Bootloader' build/logs/smoke-stock-full-vanilla.log
	grep -q 'uart: \[INFO\].CRC check pass !' build/logs/smoke-stock-full-vanilla.log
	grep -q 'gma-present .*mode=12' build/logs/smoke-stock-full-vanilla.log
	grep -q 'gma-present .*mode=6' build/logs/smoke-stock-full-vanilla.log
	grep -q 'uart: \[FS\]successed!' build/logs/smoke-stock-full-vanilla.log

smoke-stock-full-fat16: build $(STOCK_SD_IMAGE_FAT16)
	mkdir -p build/logs
	timeout 45s $(QEMU_BIN) -M sf2000 -bios $(FIRMWARE) \
		-drive if=none,id=sd0,file=$(STOCK_SD_IMAGE_FAT16),format=raw \
		-display none -serial none -monitor none \
		-d guest_errors,unimp -D build/logs/smoke-stock-full-fat16.log \
		> build/logs/smoke-stock-full-fat16.console 2>&1 || test $$? -eq 124
	grep -q 'uart:  Hichip Bootloader' build/logs/smoke-stock-full-fat16.log
	grep -q 'uart: \[INFO\].SD init cost' build/logs/smoke-stock-full-fat16.log
	grep -Eq 'uart: \[FS\]successed!|gma-present|uart: \[INFO\].----A BISRV.ASD|uart: \[ERR\].No Upgrade file -- 0:BIOS/bisrv.asd' build/logs/smoke-stock-full-fat16.log

smoke-stock-asd: build
	mkdir -p build/logs
	timeout 3s $(QEMU_BIN) -M sf2000 -bios $(FIRMWARE) -kernel $(ASD) \
		-display none -serial none -monitor none \
		-d guest_errors,unimp -D build/logs/smoke-stock-asd.log \
		> build/logs/smoke-stock-asd.console 2>&1 || test $$? -eq 124
	grep -q 'sf2000: loaded ASD' build/logs/smoke-stock-asd.console
	grep -q 'addr=0x18800002.*value=0x00001512' build/logs/smoke-stock-asd.log

smoke-stock-fatfs: build
	mkdir -p build/logs
	timeout 45s $(QEMU_BIN) -M sf2000 -bios $(FIRMWARE) -kernel $(ASD) \
		-display none -serial none -monitor none \
		-d guest_errors,unimp -D build/logs/smoke-stock-fatfs.log \
		> build/logs/smoke-stock-fatfs.console 2>&1 || test $$? -eq 124
	grep -q 'sf2000: loaded ASD' build/logs/smoke-stock-fatfs.console
	grep -q 'uart: \[FS\]successed!' build/logs/smoke-stock-fatfs.log

smoke-stock-display: build
	mkdir -p build/logs
	timeout 45s $(QEMU_BIN) -M sf2000 -bios $(FIRMWARE) -kernel $(ASD) \
		-display none -serial none -monitor none \
		-d guest_errors,unimp -D build/logs/smoke-stock-display.log \
		> build/logs/smoke-stock-display.console 2>&1 || test $$? -eq 124
	grep -q 'sf2000: loaded ASD' build/logs/smoke-stock-display.console
	grep -q 'gma-present .*mode=12' build/logs/smoke-stock-display.log
	grep -q 'gma-present .*mode=6' build/logs/smoke-stock-display.log

clean:
	rm -rf $(QEMU_SRC)/build

distclean:
	rm -rf .cache build
