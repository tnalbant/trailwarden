# CZstd — vendored Zstandard decompressor

Codex compresses older session files (`*.jsonl.zst`), and macOS ships no zstd
decoder (neither the Compression framework nor the system libarchive has one).
This target is the official decompress-only single-file build of Zstandard, so
Trailwarden can read those files offline, with no extra install.

- Source: <https://github.com/facebook/zstd>, release **v1.5.7**,
  `zstd-1.5.7.tar.gz`, SHA-256
  `eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3`
  (matches the `.sha256` published with the release).
- `zstddeclib.c` was generated, unmodified, with the release's own script:

  ```sh
  cd build/single_file_libs
  python3 combine.py -r ../../lib -x legacy/zstd_legacy.h -o zstddeclib.c zstddeclib-in.c
  ```

- `include/zstd.h` and `include/zstd_errors.h` are copied from `lib/` unchanged.
- License: Zstandard is dual-licensed BSD-3-Clause / GPLv2; Trailwarden uses it
  under the **BSD-3-Clause** license, kept here as `LICENSE`.
- Compression, legacy formats, assembly and multithreading are not built in;
  only streaming decompression is used (`ZSTD_decompressStream`).

To update: download a newer release, verify its checksum, rerun the command
above and copy the three files over these. Do not edit them by hand.
