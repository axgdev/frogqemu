QEMU_VERSION := 10.2.2
QEMU_TARBALL := qemu-$(QEMU_VERSION).tar.xz
QEMU_URL := https://download.qemu.org/$(QEMU_TARBALL)
QEMU_SRC := .cache/qemu-$(QEMU_VERSION)
QEMU_BIN := $(QEMU_SRC)/build/qemu-system-mipsel

FIRMWARE ?= /root/host-frogdev/universal/orig_firmware/SF2000_XMC_XM25QH40B_4mbit.bin
GDB ?= /opt/gdb-mips-toolchain/bin/mipsel-mti-elf-gdb
VNC ?= 127.0.0.1:1
LOG ?= build/logs/sf2000.log

.PHONY: all help deps fetch patch configure build run-vnc run-headless debug smoke clean distclean

all: build

help:
	@printf '%s\n' \
		'Targets:' \
		'  make deps          show required Alpine packages' \
		'  make build         fetch, patch, configure, and build QEMU' \
		'  make smoke         verify the sf2000 machine exists and firmware loads' \
		'  make run-vnc       run with VNC display, default 127.0.0.1:5901' \
		'  make debug         run paused with GDB stub on :1234' \
		'  make gdb           connect mipsel-mti-elf-gdb to :1234' \
		'  make clean         remove QEMU build directory only' \
		'  make distclean     remove downloaded and generated artifacts'

deps:
	@printf '%s\n' \
		'apk add --no-cache curl meson ninja patch pkgconf glib-dev pixman-dev py3-pip py3-distlib'

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
	cd $(QEMU_SRC) && patch -p1 < ../../patches/qemu-$(QEMU_VERSION)/0001-hw-mips-add-sf2000-machine.patch
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

run-vnc: build
	mkdir -p $(dir $(LOG))
	$(QEMU_BIN) -M sf2000 -bios $(FIRMWARE) \
		-display vnc=$(VNC) \
		-serial none -monitor stdio \
		-d guest_errors,unimp -D $(LOG)

run-headless: build
	mkdir -p $(dir $(LOG))
	$(QEMU_BIN) -M sf2000 -bios $(FIRMWARE) \
		-display none -serial none -monitor stdio \
		-d guest_errors,unimp -D $(LOG)

debug: build
	mkdir -p $(dir $(LOG))
	$(QEMU_BIN) -M sf2000 -bios $(FIRMWARE) \
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

clean:
	rm -rf $(QEMU_SRC)/build

distclean:
	rm -rf .cache build
