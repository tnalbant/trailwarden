#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Turgay Nalbant
#
# Builds everything a release needs: the app (signed and notarized when a
# Developer ID is present), a DMG, the CLI/MCP binaries as a tarball, and their
# checksums. Nothing is uploaded anywhere — `scripts/publish.sh` is a separate,
# deliberate step.
#
#   scripts/release.sh                              # unsigned check build
#   NOTARY_PROFILE=trailwarden scripts/release.sh    # sign + notarize + staple
#
# The Developer ID is auto-detected from the keychain; override with DEVELOPER_ID.

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(grep -m1 'MARKETING_VERSION' project.yml | cut -d'"' -f2)}"
OUT="${OUT:-$HOME/dev/.trailwarden-release}"
APP="$OUT/Build/Products/Release/Trailwarden.app"
DMG="$OUT/Trailwarden-$VERSION.dmg"
ZIP="$OUT/Trailwarden-$VERSION.zip"
TARBALL="$OUT/trailwarden-$VERSION-macos-arm64.tar.gz"

if [[ -z "${DEVELOPER_ID:-}" ]]; then
  DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)"/\1/p' | head -1)"
fi

echo "== release $VERSION =="
echo "   output: $OUT"
if [[ -n "$DEVELOPER_ID" ]]; then
  echo "   identity: $DEVELOPER_ID"
else
  echo "   identity: yok — imzasız derleme (Gatekeeper uyarır)"
fi

mkdir -p "$OUT"

echo "== generating project =="
xcodegen generate > /dev/null

echo "== building app (Release) =="
if [[ -n "$DEVELOPER_ID" ]]; then
  xcodebuild -project Trailwarden.xcodeproj -scheme Trailwarden -configuration Release \
    -derivedDataPath "$OUT" CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID" DEVELOPMENT_TEAM="${TEAM_ID:-}" build > /dev/null
else
  xcodebuild -project Trailwarden.xcodeproj -scheme Trailwarden -configuration Release \
    -derivedDataPath "$OUT" CODE_SIGNING_ALLOWED=NO build > /dev/null
fi

if [[ -n "$DEVELOPER_ID" ]]; then
  echo "== signing =="
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"

  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "== notarizing (bu birkaç dakika sürebilir) =="
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    echo "== gatekeeper kontrolü =="
    spctl -a -vv "$APP"
  else
    echo "   not: NOTARY_PROFILE verilmedi — notarization atlandı"
  fi
fi

echo "== packing DMG =="
rm -f "$DMG"
hdiutil create -volname "Trailwarden $VERSION" -srcfolder "$APP" -ov -format UDZO "$DMG" > /dev/null
if [[ -n "$DEVELOPER_ID" ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
fi

echo "== building CLI + MCP =="
swift build -c release --product trailwarden > /dev/null
swift build -c release --product trailwarden-mcp > /dev/null
rm -f "$TARBALL"
mkdir -p "$OUT/trailwarden-$VERSION-macos-arm64"
cp .build/release/trailwarden .build/release/trailwarden-mcp "$OUT/trailwarden-$VERSION-macos-arm64/"
cp LICENSE README.md "$OUT/trailwarden-$VERSION-macos-arm64/"
tar -czf "$TARBALL" -C "$OUT" "trailwarden-$VERSION-macos-arm64"
rm -rf "$OUT/trailwarden-$VERSION-macos-arm64"

echo "== checksums =="
( cd "$OUT" && shasum -a 256 "$(basename "$DMG")" "$(basename "$TARBALL")" | tee SHA256SUMS )

echo
echo "hazır:"
echo "  $DMG"
echo "  $TARBALL"
echo "  $OUT/SHA256SUMS"
if [[ -z "$DEVELOPER_ID" ]]; then
  echo
  echo "not: imzasız derleme. Developer ID Application sertifikası kurulunca"
  echo "     NOTARY_PROFILE=trailwarden scripts/release.sh ile imzalı+notarized üretilir."
fi
