# Zig GitHub Mirror Automation

This repository uses two branches:

- `master`: mirrors upstream `https://codeberg.org/ziglang/zig` `master`
- `main`: holds GitHub automation only

The scheduled workflow on `main` force-syncs `master` from Codeberg every 6 hours and compiles release assets from the synced source tree when upstream changes.

Release artifacts are built from the synced `master` branch source, not from the automation branch.

The workflow uses the published Zig bootstrap source tarball as a build seed for LLVM/Clang/LLD/zlib/zstd sources. If the seed's bundled LLVM major does not match the synced Zig source requirement, automation now automatically overlays LLVM/Clang/LLD/cmake from `llvm-project` `release/<major>.x` before compiling.

The uploaded release assets are freshly compiled in GitHub Actions from the synced Codeberg commit rather than mirrored from `https://ziglang.org/download/`.

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
