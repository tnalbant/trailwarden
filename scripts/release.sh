#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Turgay Nalbant
#
# Builds a Release app, signs and notarizes it when the credentials are present,
# and packs a DMG. Nothing is uploaded anywhere.
#
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" \
#   NOTARY_PROFILE="trailwarden" scripts/release.sh
#
# Without DEVELOPER_ID it still builds and produces an unsigned DMG, which is
# what a local check needs.

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(grep -m1 'MARKETING_VERSION' project.yml | cut -d'"' -f2)}"
BUILD_DIR="$HOME/dev/.trailwarden-release"
APP="$BUILD_DIR/Build/Products/Release/Trailwarden.app"
DMG="$BUILD_DIR/Trailwarden-$VERSION.dmg"

echo "== generating project =="
xcodegen generate

echo "== building Release =="
xcodebuild -project Trailwarden.xcodeproj -scheme Trailwarden -configuration Release \
  -derivedDataPath "$BUILD_DIR" CODE_SIGNING_ALLOWED="${DEVELOPER_ID:+YES}" \
  CODE_SIGNING_ALLOWED="${DEVELOPER_ID:-NO}" build

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "== signing =="
  codesign --deep --force --options runtime --timestamp \
    --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"

  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "== notarizing =="
    ditto -c -k --keepParent "$APP" "$BUILD_DIR/Trailwarden.zip"
    xcrun notarytool submit "$BUILD_DIR/Trailwarden.zip" \
      --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
  fi
fi

echo "== packing DMG =="
rm -f "$DMG"
hdiutil create -volname "Trailwarden $VERSION" -srcfolder "$APP" -ov -format UDZO "$DMG"

echo "ok: $DMG"
if [[ -z "${DEVELOPER_ID:-}" ]]; then
  echo "note: unsigned build — Gatekeeper will warn on first open"
fi
