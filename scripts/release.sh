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
# Team id lives in the identity string: "Developer ID Application: Name (TEAMID)"
if [[ -z "${TEAM_ID:-}" && -n "$DEVELOPER_ID" ]]; then
  TEAM_ID="$(sed -n 's/.*(\([A-Z0-9]*\))$/\1/p' <<< "$DEVELOPER_ID")"
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
# Always build unsigned, then sign the bundle ourselves. Xcode's signing step
# wants a provisioning profile even for Developer ID, which a non-sandboxed app
# does not have; codesign gives the same result with fewer moving parts.
if ! xcodebuild -project Trailwarden.xcodeproj -scheme Trailwarden -configuration Release \
  -derivedDataPath "$OUT" CODE_SIGNING_ALLOWED=NO build > "$OUT/build.log" 2>&1; then
  echo "HATA: derleme başarısız — ayrıntı: $OUT/build.log" >&2
  grep -E "error:" "$OUT/build.log" | head -10 >&2
  exit 1
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
  # The app inside is notarized, but the disk image that carries it is a separate
  # object: without its own ticket macOS reports "Unnotarized Developer ID" when
  # the download is opened from Safari or a browser-managed quarantine.
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "== notarizing the DMG =="
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl -a -t open --context context:primary-signature -vv "$DMG"
  fi
fi

echo "== building CLI + MCP =="
swift build -c release --product trailwarden > /dev/null
swift build -c release --product trailwarden-mcp > /dev/null
rm -f "$TARBALL"
mkdir -p "$OUT/trailwarden-$VERSION-macos-arm64"
cp .build/release/trailwarden .build/release/trailwarden-mcp "$OUT/trailwarden-$VERSION-macos-arm64/"
cp LICENSE README.md "$OUT/trailwarden-$VERSION-macos-arm64/"
cp Sources/TrailwardenApp/Resources/Acknowledgements.txt "$OUT/trailwarden-$VERSION-macos-arm64/"
tar -czf "$TARBALL" -C "$OUT" "trailwarden-$VERSION-macos-arm64"
rm -rf "$OUT/trailwarden-$VERSION-macos-arm64"

echo "== update feed =="
# The app's "Check for updates" reads latest.json from the newest GitHub release
# (UpdateChecker.publishedFeed). It carries the version, one sentence of notes —
# the first paragraph of docs/RELEASE_NOTES.md — and the release page.
NOTES_FILE="docs/RELEASE_NOTES.md"
if [[ ! -f "$NOTES_FILE" ]]; then
  echo "HATA: $NOTES_FILE yok — sürüm notları olmadan yayın yapılmaz." >&2
  exit 1
fi
python3 - "$VERSION" "$NOTES_FILE" "$OUT/latest.json" <<'PY'
import json, sys
version, notes_path, out = sys.argv[1:4]
summary = ""
for line in open(notes_path, encoding="utf-8"):
    text = line.strip()
    if not text or text.startswith("#") or text.startswith("<!--"):
        if summary:
            break
        continue
    summary = (summary + " " + text).strip()
feed = {
    "version": version,
    "notes": summary,
    "url": f"https://github.com/tnalbant/trailwarden/releases/tag/v{version}",
}
with open(out, "w", encoding="utf-8") as handle:
    json.dump(feed, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print("   " + json.dumps(feed, ensure_ascii=False))
PY

echo "== checksums =="
( cd "$OUT" && shasum -a 256 "$(basename "$DMG")" "$(basename "$TARBALL")" latest.json | tee SHA256SUMS )

echo
echo "hazır:"
echo "  $DMG"
echo "  $TARBALL"
echo "  $OUT/latest.json"
echo "  $OUT/SHA256SUMS"
if [[ -z "$DEVELOPER_ID" ]]; then
  echo
  echo "not: imzasız derleme. Developer ID Application sertifikası kurulunca"
  echo "     NOTARY_PROFILE=trailwarden scripts/release.sh ile imzalı+notarized üretilir."
fi
