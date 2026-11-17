#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Turgay Nalbant
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
TARBALL="$OUT/trailwarden-$VERSION-macos-arm64.tar.gz"
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
  DMG_SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
  TAR_SHA="$(curl -sL "https://github.com/tnalbant/trailwarden/archive/refs/tags/v$VERSION.tar.gz" | shasum -a 256 | cut -d' ' -f1)"
  sed -i '' "s/^  version .*/  version \"$VERSION\"/; s/^  sha256 .*/  sha256 \"$DMG_SHA\"/" \
    "$TAP_DIR/Casks/trailwarden.rb"
  sed -i '' "s|/v[0-9.]*\\.tar\\.gz|/v$VERSION.tar.gz|; s/^  sha256 .*/  sha256 \"$TAR_SHA\"/" \
    "$TAP_DIR/Formula/trailwarden-cli.rb"
  ( cd "$TAP_DIR" && git add -A && git commit -m "trailwarden $VERSION" && git push )
fi

if [[ $DO_NPM -eq 1 ]]; then
  echo "== npm =="
  ( cd packaging/npm && npm publish --access public )
fi

echo "done."
