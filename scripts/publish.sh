#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 tnalbant
#
# Publishes a release that `scripts/release.sh` already built. Every step is
# external, so nothing runs without an explicit flag — dry run is the default.
#
#   scripts/publish.sh --release            # tag + GitHub release + artifacts
#   scripts/publish.sh --tap                # update tnalbant/homebrew-trailwarden
#   scripts/publish.sh --npm                # npm publish trailwarden-mcp
#   scripts/publish.sh --all --yes
#
# The tag is created only if the working tree is clean and, when RELEASE_GATE
# names an extra pre-release check (a script run as `$RELEASE_GATE . --fast`),
# that check passes.

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(grep -m1 'MARKETING_VERSION' project.yml | cut -d'"' -f2)}"
OUT="${OUT:-$HOME/dev/.trailwarden-release}"
DMG="$OUT/Trailwarden-$VERSION.dmg"
TARBALL="$OUT/trailwarden-$VERSION-macos-universal.tar.gz"
SUMS="$OUT/SHA256SUMS"
FEED="$OUT/latest.json"
TAP_DIR="${TAP_DIR:-$HOME/dev/homebrew-trailwarden}"

DO_RELEASE=0
DO_TAP=0
DO_NPM=0
CONFIRMED=0

for arg in "$@"; do
  case "$arg" in
    --release) DO_RELEASE=1 ;;
    --tap) DO_TAP=1 ;;
    --npm) DO_NPM=1 ;;
    --all) DO_RELEASE=1; DO_TAP=1; DO_NPM=1 ;;
    --yes) CONFIRMED=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if [[ $((DO_RELEASE + DO_TAP + DO_NPM)) -eq 0 ]]; then
  echo "no step selected. Example: scripts/publish.sh --release --yes" >&2
  exit 2
fi

echo "== pre-release checks =="
if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: the working tree is not clean." >&2
  exit 1
fi
if [[ -n "${RELEASE_GATE:-}" ]]; then
  python3 "$RELEASE_GATE" . --fast || {
    echo "ERROR: the release gate did not pass." >&2
    exit 1
  }
fi
for file in "$DMG" "$TARBALL" "$SUMS" "$FEED" docs/RELEASE_NOTES.md; do
  [[ -f "$file" ]] || { echo "ERROR: missing file: $file (run scripts/release.sh first)" >&2; exit 1; }
done
# Nothing that names this machine may ship: not in the tree, not anywhere in
# the history the tag will point into, not inside the files to be uploaded.
scripts/privacy-check.sh --tree --history --artifacts "$DMG" "$TARBALL" "$SUMS" "$FEED" || {
  echo "ERROR: the privacy gate did not pass; nothing was published." >&2
  exit 1
}

# release.sh skips notarization when NOTARY_PROFILE is unset and says so once;
# that build must never reach users. The disk image has to carry its own
# stapled ticket and pass Gatekeeper, and so do the binaries in the tarball.
if [[ $DO_RELEASE -eq 1 || $DO_TAP -eq 1 ]]; then
  xcrun stapler validate -q "$DMG" \
    || { echo "ERROR: $DMG has no notarization ticket (NOTARY_PROFILE=… scripts/release.sh)" >&2; exit 1; }
  spctl -a -t open --context context:primary-signature "$DMG" 2>/dev/null \
    || { echo "ERROR: Gatekeeper rejects $DMG" >&2; exit 1; }
  CHECK_DIR="$(mktemp -d)"
  tar -xzf "$TARBALL" -C "$CHECK_DIR"
  for binary in "$CHECK_DIR"/*/trailwarden "$CHECK_DIR"/*/trailwarden-mcp; do
    spctl -a -t install "$binary" 2>/dev/null \
      || { echo "ERROR: Gatekeeper rejects $(basename "$binary") in the tarball (not notarized)" >&2; rm -rf "$CHECK_DIR"; exit 1; }
  done
  rm -rf "$CHECK_DIR"
  echo "   notarized: DMG and CLI binaries"
fi

if [[ $CONFIRMED -eq 0 ]]; then
  echo
  echo "dry run — would do:"
  [[ $DO_RELEASE -eq 1 ]] && echo "  · git tag v$VERSION + push + gh release create with 4 files (latest.json included)"
  [[ $DO_TAP -eq 1 ]] && echo "  · update cask/formula sha256 in $TAP_DIR + push"
  [[ $DO_NPM -eq 1 ]] && echo "  · npm publish packaging/npm (public)"
  echo
  echo "add --yes to run it."
  exit 0
fi

if [[ $DO_RELEASE -eq 1 ]]; then
  echo "== GitHub release =="
  git tag -a "v$VERSION" -m "Trailwarden $VERSION"
  git push origin "v$VERSION"
  # latest.json must travel with every release: the app's update check reads it
  # through GitHub's releases/latest/download/ redirect.
  gh release create "v$VERSION" "$DMG" "$TARBALL" "$SUMS" "$FEED" \
    --title "Trailwarden $VERSION" --notes-file docs/RELEASE_NOTES.md
fi

if [[ $DO_TAP -eq 1 ]]; then
  echo "== tap update =="
  [[ -d "$TAP_DIR/.git" ]] || { echo "ERROR: no tap repository at $TAP_DIR" >&2; exit 1; }
  # The tap gets this repository's cask and formula as they are, then this
  # release's version and checksums: a change made in packaging/homebrew ships
  # with the next release instead of staying behind.
  cp packaging/homebrew/Casks/trailwarden.rb "$TAP_DIR/Casks/trailwarden.rb"
  cp packaging/homebrew/Formula/trailwarden-cli.rb "$TAP_DIR/Formula/trailwarden-cli.rb"
  DMG_SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
  TAR_SHA="$(curl -sL "https://github.com/tnalbant/trailwarden/archive/refs/tags/v$VERSION.tar.gz" | shasum -a 256 | cut -d' ' -f1)"
  sed -i '' "s/^  version .*/  version \"$VERSION\"/; s/^  sha256 .*/  sha256 \"$DMG_SHA\"/" \
    "$TAP_DIR/Casks/trailwarden.rb"
  sed -i '' "s|/v[0-9.]*\\.tar\\.gz|/v$VERSION.tar.gz|; s/^  sha256 .*/  sha256 \"$TAR_SHA\"/" \
    "$TAP_DIR/Formula/trailwarden-cli.rb"
  # sed changes nothing when a line it looks for is gone; check the result
  # instead of trusting it.
  grep -q "^  version \"$VERSION\"$" "$TAP_DIR/Casks/trailwarden.rb" \
    && grep -q "^  sha256 \"$DMG_SHA\"$" "$TAP_DIR/Casks/trailwarden.rb" \
    && grep -q "/v$VERSION.tar.gz\"$" "$TAP_DIR/Formula/trailwarden-cli.rb" \
    && grep -q "^  sha256 \"$TAR_SHA\"$" "$TAP_DIR/Formula/trailwarden-cli.rb" \
    || { echo "ERROR: the tap files did not take version $VERSION and its checksums" >&2; exit 1; }
  if grep -q "REPLACE_WITH_" "$TAP_DIR/Casks/trailwarden.rb" "$TAP_DIR/Formula/trailwarden-cli.rb"; then
    echo "ERROR: a placeholder is left in the tap files" >&2
    exit 1
  fi
  ( cd "$TAP_DIR" && git add -A && git commit -m "trailwarden $VERSION" && git push )
fi

if [[ $DO_NPM -eq 1 ]]; then
  echo "== npm =="
  # prepack takes the signed binary from $OUT/signed and refuses anything that
  # Gatekeeper would reject; it needs to know where release.sh wrote.
  # Pack once, check that exact tarball, publish that file: what the gate read
  # is byte for byte what npm receives.
  PACK_DIR="$(mktemp -d)"
  ( cd packaging/npm && TRAILWARDEN_RELEASE_OUT="$OUT" npm pack --pack-destination "$PACK_DIR" > /dev/null )
  NPM_TGZ="$(ls "$PACK_DIR"/*.tgz)"
  scripts/privacy-check.sh --artifacts "$NPM_TGZ" || {
    echo "ERROR: the privacy gate rejected the npm tarball; nothing was published." >&2
    rm -rf "$PACK_DIR"; exit 1
  }
  npm publish "$NPM_TGZ" --access public
  rm -rf "$PACK_DIR"
fi

echo "done."
