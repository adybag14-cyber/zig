# Zig GitHub Mirror Automation

This repository uses two branches:

- `master`: mirrors upstream `https://codeberg.org/ziglang/zig` `master`
- `main`: holds GitHub automation only

The scheduled workflow on `main` force-syncs `master` from Codeberg every 6 hours and publishes portable source-build release assets when upstream changes.

Release artifacts are built from the synced `master` branch source, not from the automation branch.

It publishes GitHub-hosted builds for:

- `zig-linux-x86_64`
- `zig-linux-aarch64`
- `zig-windows-x86_64`
- `zig-windows-aarch64`
- `zig-macos-aarch64`

It publishes two release styles:

- immutable per-commit prereleases such as `upstream-<shortsha>`
- a rolling `latest-master` prerelease with stable asset names for "give me the newest build"

This is the GitHub-hosted release subset of the upstream Codeberg CI matrix. Platforms that still require upstream self-hosted runners are not mirrored here.
