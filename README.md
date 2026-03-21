# Zig GitHub Mirror Automation

This repository uses two branches:

- `master`: mirrors upstream `https://codeberg.org/ziglang/zig` `master`
- `main`: holds GitHub automation only

The scheduled workflow on `main` force-syncs `master` from Codeberg every 6 hours and compiles release assets from the synced source tree when upstream changes.

Release artifacts are built from the synced `master` branch source, not from the automation branch.

The workflow uses the published Zig bootstrap source tarball only as a build seed for LLVM/Clang/LLD/zlib/zstd sources. The uploaded release assets are freshly compiled in GitHub Actions from the synced Codeberg commit rather than mirrored from `https://ziglang.org/download/`.

The current compiled release set includes:

- `zig-x86_64-linux`
- `zig-aarch64-linux`
- `zig-x86_64-windows`
- `zig-aarch64-windows`
- `zig-x86_64-macos`
- `zig-aarch64-macos`

It publishes two release styles:

- immutable per-commit prereleases such as `upstream-<shortsha>`
- a rolling `latest-master` prerelease with stable asset names for "give me the newest build"

`workflow_dispatch` also accepts a `release_scope` input so a single group can be rebuilt for validation without publishing a partial release.
