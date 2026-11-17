# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Turgay Nalbant
#
# Formula for the command line tool and the MCP server, built from source.
#   brew install tnalbant/trailwarden/trailwarden-cli
#
# `sha256` is filled in by scripts/publish.sh from the tag's tarball.

class TrailwardenCli < Formula
  desc "Local audit trail for coding agents (CLI + MCP server)"
  homepage "https://github.com/tnalbant/trailwarden"
  url "https://github.com/tnalbant/trailwarden/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "REPLACE_WITH_TARBALL_SHA256"
  license "Apache-2.0"

  depends_on :macos
  depends_on xcode: ["16.0", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/trailwarden"
    bin.install ".build/release/trailwarden-mcp"
  end

  test do
    assert_match "OVERVIEW", shell_output("#{bin}/trailwarden --help")
  end
end
