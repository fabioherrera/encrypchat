# Encrypchat monorepo helpers
# Optional local Flutter: .tools/flutter (gitignored)

ROOT := $(CURDIR)
FLUTTER ?= $(shell if [ -x $(ROOT)/.tools/flutter/bin/flutter ]; then echo $(ROOT)/.tools/flutter/bin/flutter; else command -v flutter; fi)
export PATH := $(dir $(abspath $(FLUTTER))):$(PATH)
export PUB_CACHE ?= $(ROOT)/.tools/pub-cache
# Isolated HOME only for Flutter (avoids writing to real ~; keeps rustup working for cargo)
FLUTTER_HOME := $(ROOT)/.tools/home

.PHONY: check check-rust check-web check-client dev-web dev-client help

help:
	@echo "Targets: check | check-rust | check-web | check-client | dev-web | dev-client"

check: check-rust check-web check-client

check-rust:
	cargo test -p encrypchat_core
	cargo build -p encrypchat_relay

check-web:
	cd apps/web && npm run build

check-client:
	mkdir -p $(PUB_CACHE) $(FLUTTER_HOME)
	cd apps/client && HOME=$(FLUTTER_HOME) PUB_CACHE=$(PUB_CACHE) $(FLUTTER) test
	@echo "Client tests OK (linux/cmake package builds need system deps — Phase 8)"

dev-web:
	cd apps/web && npm run dev

dev-client:
	mkdir -p $(PUB_CACHE) $(FLUTTER_HOME)
	cd apps/client && HOME=$(FLUTTER_HOME) PUB_CACHE=$(PUB_CACHE) $(FLUTTER) run -d linux
