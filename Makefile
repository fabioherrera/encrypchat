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

# Keep the builder's home directory out of the binaries: a panic message names the source
# file that raised it, and the crate registry sits under .tools/. scripts/common.sh sets the
# identical flag so packaging and `make check` share one cargo fingerprint.
export RUSTFLAGS := --remap-path-prefix=$(ROOT)=/encrypchat $(RUSTFLAGS)

# The web build is offline by design (fonts are self-hosted); telemetry was the
# only outbound call left. Also keeps builds identical with and without network.
export NEXT_TELEMETRY_DISABLED := 1

.PHONY: check check-rust check-web check-client check-security-txt build-ffi \
	build-client-linux package package-linux package-rpm package-android help

help:
	@echo "Targets: check | check-rust | check-web | check-client | check-security-txt | build-ffi | build-client-linux | package | package-linux | package-rpm | package-android | dev-web | dev-client"
	@echo "Toolchain: put cmake/ninja in .tools/bin if system packages are unavailable"
	@echo "Packaging: make package → dist/ (see dist/README.md, docs/phase-8.md)"

# First because it costs a second and its failure is a deadline, not a bug: better to hear
# about it before a ten-minute build than after one.
check: check-security-txt check-rust check-web build-ffi check-client

check-security-txt:
	$(ROOT)/scripts/check-security-txt.sh

check-rust:
	cargo fmt --all --check
	cargo clippy --workspace --all-targets -- -D warnings
	cargo test -p encrypchat_core
	cargo test -p encrypchat_relay
	cargo build -p encrypchat_relay

run-relay:
	cargo run -p encrypchat_relay

build-ffi:
	cargo build -p encrypchat_core --release
	mkdir -p $(ROOT)/apps/client/native
	cp -f $(CARGO_TARGET_DIR)/release/libencrypchat_core.so $(ROOT)/apps/client/native/libencrypchat_core.so
	@echo "FFI lib → apps/client/native/libencrypchat_core.so"

check-web:
	# Clean start every time: fonts are self-hosted, so no build cache is worth
	# keeping and no network is needed. This also refreshes out/, the artifact
	# that gets deployed. NEXT_DIST_DIR was tried here and does not isolate the
	# build — it only moves the export, which left out/ silently stale — so do
	# not run this while `next dev` is up: both own .next and the build fails
	# at random with "Cannot find module for page".
	cd apps/web && rm -rf .next out && npm run build

check-client: build-ffi
	mkdir -p $(PUB_CACHE) $(FLUTTER_HOME)
	cd apps/client && HOME=$(FLUTTER_HOME) PUB_CACHE=$(PUB_CACHE) $(FLUTTER) pub get
	cd apps/client && HOME=$(FLUTTER_HOME) PUB_CACHE=$(PUB_CACHE) \
		dart format --output=none --set-exit-if-changed .
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
	cd apps/web && npm run dev

package-linux:
	$(ROOT)/scripts/package-linux.sh

# Fedora. The tarball installs into the user prefix and leaves nothing to track; this one
# `dnf remove` takes back out whole, which is what you want on a machine used for testing.
package-rpm:
	$(ROOT)/scripts/package-rpm.sh

package-android:
	$(ROOT)/scripts/package-android.sh

package:
	$(ROOT)/scripts/package-all.sh
