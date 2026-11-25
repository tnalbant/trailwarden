#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 tnalbant
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
TARBALL="$OUT/trailwarden-$VERSION-macos-universal.tar.gz"

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
  echo "   identity: none — unsigned build (Gatekeeper will warn)"
fi

mkdir -p "$OUT"

echo "== generating project =="
xcodegen generate > /dev/null

echo "== building app (Release) =="
# Always build unsigned, then sign the bundle ourselves. Xcode's signing step
# wants a provisioning profile even for Developer ID, which a non-sandboxed app
# does not have; codesign gives the same result with fewer moving parts.
if ! xcodebuild -project Trailwarden.xcodeproj -scheme Trailwarden -configuration Release \
  -derivedDataPath "$OUT" CODE_SIGNING_ALLOWED=NO \
  OTHER_SWIFT_FLAGS="\$(inherited) -debug-prefix-map $PWD=. -file-prefix-map $PWD=. -debug-prefix-map $HOME=." \
  OTHER_LDFLAGS="\$(inherited) -Wl,-oso_prefix,$HOME" \
  build > "$OUT/build.log" 2>&1; then
  echo "ERROR: build failed — see $OUT/build.log" >&2
  grep -E "error:" "$OUT/build.log" | head -10 >&2
  exit 1
fi

# Same as the CLI below: no local symbols, then a signature again.
find "$APP/Contents/MacOS" -type f -perm -u+x -exec strip -S -x {} +
[[ -n "$DEVELOPER_ID" ]] || codesign --force --deep --sign - "$APP"

if [[ -n "$DEVELOPER_ID" ]]; then
  echo "== signing =="
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"

  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "== notarizing (this can take a few minutes) =="
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    echo "== gatekeeper check =="
    spctl -a -vv "$APP"
  else
    echo "   note: no NOTARY_PROFILE — notarization skipped"
  fi
fi

echo "== packing DMG =="
# The app next to an /Applications link, so the window that opens says what to do:
# drag one onto the other.
STAGE="$OUT/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Trailwarden.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Trailwarden $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" > /dev/null
rm -rf "$STAGE"
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

echo "== building CLI + MCP (arm64 + x86_64) =="
# One universal build serves the tarball and the npm package alike. The prefix
# maps keep this checkout's absolute path and $HOME out of debug info, #file
# literals and the linker's object-file paths; strip removes what is left of the
# local symbol table. scripts/privacy-check.sh reads the result as bytes.
UNIVERSAL=(-c release --arch arm64 --arch x86_64
  -Xswiftc -debug-prefix-map -Xswiftc "$PWD=."
  -Xswiftc -file-prefix-map -Xswiftc "$PWD=."
  -Xswiftc -debug-prefix-map -Xswiftc "$HOME=."
  -Xlinker -oso_prefix -Xlinker "$HOME")
swift build "${UNIVERSAL[@]}" --product trailwarden > /dev/null
swift build "${UNIVERSAL[@]}" --product trailwarden-mcp > /dev/null
BIN="$(swift build "${UNIVERSAL[@]}" --show-bin-path)"
CLI_DIR="$OUT/trailwarden-$VERSION-macos-universal"
rm -rf "$CLI_DIR" "$TARBALL"
mkdir -p "$CLI_DIR"
cp "$BIN/trailwarden" "$BIN/trailwarden-mcp" "$CLI_DIR/"
strip -S -x "$CLI_DIR/trailwarden" "$CLI_DIR/trailwarden-mcp"
# strip drops the linker's ad-hoc signature; arm64 refuses to run unsigned code.
[[ -n "$DEVELOPER_ID" ]] || codesign --force --sign - "$CLI_DIR/trailwarden" "$CLI_DIR/trailwarden-mcp"
if [[ -n "$DEVELOPER_ID" ]]; then
  # A tarball opened from a browser is quarantined like any download; signed and
  # notarized binaries pass Gatekeeper instead of being refused as unidentified.
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" \
    "$CLI_DIR/trailwarden" "$CLI_DIR/trailwarden-mcp"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "== notarizing CLI + MCP =="
    CLI_ZIP="$OUT/cli-notarize.zip"
    rm -f "$CLI_ZIP"
    ditto -c -k --keepParent "$CLI_DIR" "$CLI_ZIP"
    xcrun notarytool submit "$CLI_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    rm -f "$CLI_ZIP"
  fi
fi
# Keep the signed binaries: the npm package ships these exact files
# (packaging/npm/scripts/prepack.js), not an ad-hoc signed build.
rm -rf "$OUT/signed"
mkdir -p "$OUT/signed"
cp "$CLI_DIR/trailwarden" "$CLI_DIR/trailwarden-mcp" "$OUT/signed/"
cp LICENSE README.md "$CLI_DIR/"
cp Sources/TrailwardenApp/Resources/Acknowledgements.txt "$CLI_DIR/"
tar -czf "$TARBALL" -C "$OUT" "$(basename "$CLI_DIR")"
rm -rf "$CLI_DIR"

echo "== update feed =="
# The app's "Check for updates" reads latest.json from the newest GitHub release
# (UpdateChecker.publishedFeed). It carries the version, one sentence of notes —
# the first paragraph of docs/RELEASE_NOTES.md — and the release page.
NOTES_FILE="docs/RELEASE_NOTES.md"
if [[ ! -f "$NOTES_FILE" ]]; then
  echo "ERROR: $NOTES_FILE is missing — no release without release notes." >&2
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

echo "== privacy gate =="
scripts/privacy-check.sh --artifacts "$DMG" "$TARBALL" "$OUT/latest.json"

echo "== checksums =="
( cd "$OUT" && shasum -a 256 "$(basename "$DMG")" "$(basename "$TARBALL")" latest.json | tee SHA256SUMS )

echo
echo "ready:"
echo "  $DMG"
echo "  $TARBALL"
echo "  $OUT/latest.json"
echo "  $OUT/SHA256SUMS"
if [[ -z "$DEVELOPER_ID" ]]; then
  echo
  echo "note: unsigned build. With a Developer ID Application certificate installed,"
  echo "      NOTARY_PROFILE=trailwarden scripts/release.sh produces a signed, notarized one."
fi
