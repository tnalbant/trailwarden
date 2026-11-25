#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 tnalbant
#
# Renders the app icon and the menu bar glyph from docs/brand/*.svg into the
# asset catalogue. Needs rsvg-convert (brew install librsvg).
set -eu
cd "$(dirname "$0")/.."
assets=Sources/TrailwardenApp/Resources/Assets.xcassets
for size in 16 32 64 128 256 512 1024; do
    rsvg-convert -w "$size" -h "$size" docs/brand/AppIcon.svg \
        -o "$assets/AppIcon.appiconset/icon_$size.png"
done
for scale in 1 2; do
    px=$((18 * scale))
    rsvg-convert -w "$px" -h "$px" docs/brand/MenuBarIcon.svg \
        -o "$assets/MenuBarIcon.imageset/menubar@${scale}x.png"
done
echo "icons rendered into $assets"
