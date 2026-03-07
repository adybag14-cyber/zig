# Zig GitHub Mirror Automation

This repository uses two branches:

- `master`: mirrors upstream `https://codeberg.org/ziglang/zig` `master`
- `main`: holds GitHub automation only

The scheduled workflow on `main` force-syncs `master` from Codeberg every 8 hours and publishes a portable Windows source-build zip as a GitHub release asset when upstream changes.

Release artifacts are built from the synced `master` branch source, not from the automation branch.

It publishes two release styles:

- immutable per-commit prereleases such as `upstream-<shortsha>`
- a rolling `latest-master` prerelease with a stable asset name for "give me the newest build"
