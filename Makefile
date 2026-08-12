# Encrypchat monorepo helpers
# Optional local Flutter: .tools/flutter (gitignored)

ROOT := $(CURDIR)
FLUTTER ?= $(shell if [ -x $(ROOT)/.tools/flutter/bin/flutter ]; then echo $(ROOT)/.tools/flutter/bin/flutter; else command -v flutter; fi)
# Prefer portable toolchain under .tools/bin (cmake/ninja) when present
export PATH := $(ROOT)/.tools/bin:$(dir $(abspath $(FLUTTER))):$(PATH)
export PUB_CACHE ?= $(ROOT)/.tools/pub-cache
# Isolated HOME only for Flutter (avoids writing to real ~; keeps rustup working for cargo)
FLUTTER_HOME := $(ROOT)/.tools/home

# Prefer repo-local target dir so `native/` can be populated without sandbox cache paths.
export CARGO_TARGET_DIR ?= $(ROOT)/target

.PHONY: check check-rust check-web check-client build-ffi build-client-linux \
	package package-linux package-android help

help:
	@echo "Targets: check | check-rust | check-web | check-client | build-ffi | build-client-linux | package | package-linux | package-android | dev-web | dev-client"
	@echo "Toolchain: put cmake/ninja in .tools/bin if system packages are unavailable"
	@echo "Packaging: make package → dist/ (see dist/README.md, docs/phase-8.md)"

check: check-rust check-web build-ffi check-client

check-rust:
	cargo test -p encrypchat_core
	cargo build -p encrypchat_relay

build-ffi:
	cargo build -p encrypchat_core --release
	mkdir -p $(ROOT)/apps/client/native
	cp -f $(CARGO_TARGET_DIR)/release/libencrypchat_core.so $(ROOT)/apps/client/native/libencrypchat_core.so
	@echo "FFI lib → apps/client/native/libencrypchat_core.so"

check-web:
	cd apps/web && npm run build

check-client: build-ffi
	mkdir -p $(PUB_CACHE) $(FLUTTER_HOME)
	cd apps/client && HOME=$(FLUTTER_HOME) PUB_CACHE=$(PUB_CACHE) $(FLUTTER) pub get
	cd apps/client && HOME=$(FLUTTER_HOME) PUB_CACHE=$(PUB_CACHE) \
		ENCRYPCHAT_CORE_LIB=$(ROOT)/apps/client/native/libencrypchat_core.so \
		$(FLUTTER) test
	@echo "Client tests OK (linux/cmake package builds need system deps — Phase 8)"

build-client-linux: build-ffi
	mkdir -p $(PUB_CACHE) $(FLUTTER_HOME)
	cd apps/client && HOME=$(FLUTTER_HOME) PUB_CACHE=$(PUB_CACHE) $(FLUTTER) pub get
	cd apps/client && HOME=$(FLUTTER_HOME) PUB_CACHE=$(PUB_CACHE) \
		ENCRYPCHAT_CORE_LIB=$(ROOT)/apps/client/native/libencrypchat_core.so \
		PKG_CONFIG_PATH=$(ROOT)/.tools/pkgconfig:$${PKG_CONFIG_PATH} \
		$(FLUTTER) build linux
	@echo "Linux bundle: apps/client/build/linux/x64/release/bundle/encrypchat"

dev-client: build-ffi
	mkdir -p $(PUB_CACHE) $(FLUTTER_HOME)
	cd apps/client && HOME=$(FLUTTER_HOME) PUB_CACHE=$(PUB_CACHE) $(FLUTTER) pub get
	cd apps/client && HOME=$(FLUTTER_HOME) PUB_CACHE=$(PUB_CACHE) \
		ENCRYPCHAT_CORE_LIB=$(ROOT)/apps/client/native/libencrypchat_core.so \
		PKG_CONFIG_PATH=$(ROOT)/.tools/pkgconfig:$${PKG_CONFIG_PATH} \
		$(FLUTTER) run -d linux

dev-web:
	cd apps/web && npm run build >/dev/null 2>&1 || true
	cd apps/web && npm run dev

package-linux:
	$(ROOT)/scripts/package-linux.sh

package-android:
	$(ROOT)/scripts/package-android.sh

package:
	$(ROOT)/scripts/package-all.sh
