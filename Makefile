# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Turgay Nalbant

PREFIX ?= /usr/local

.PHONY: help build test install uninstall app run release clean

help:
	@echo "make build     - CLI ve MCP ikili dosyalarini derle"
	@echo "make test      - testleri kos"
	@echo "make install   - CLI + MCP dosyalarini $(PREFIX)/bin icine kur"
	@echo "make app       - masaustu uygulamasini derle (Release)"
	@echo "make run       - uygulamayi ac"
	@echo "make release   - DMG + tarball + sha256 uret (scripts/release.sh)"

build:
	swift build -c release

test:
	swift test

install: build
	install -d $(PREFIX)/bin
	install -m 755 .build/release/trailwarden $(PREFIX)/bin/trailwarden
	install -m 755 .build/release/trailwarden-mcp $(PREFIX)/bin/trailwarden-mcp
	@echo "kuruldu: $(PREFIX)/bin/trailwarden"

uninstall:
	rm -f $(PREFIX)/bin/trailwarden $(PREFIX)/bin/trailwarden-mcp

app:
	xcodegen generate > /dev/null
	xcodebuild -project Trailwarden.xcodeproj -scheme Trailwarden -configuration Release \
	  -derivedDataPath $$HOME/dev/.trailwarden-derived CODE_SIGNING_ALLOWED=NO build | tail -2

run: app
	open $$HOME/dev/.trailwarden-derived/Build/Products/Release/Trailwarden.app

release:
	scripts/release.sh

clean:
	swift package clean
	rm -rf Trailwarden.xcodeproj
