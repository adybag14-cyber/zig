# Zig GitHub Mirror Automation

This repository uses two branches:

- `master`: mirrors upstream `https://codeberg.org/ziglang/zig` `master`
- `main`: holds GitHub automation only

The scheduled workflow on `main` force-syncs `master` from Codeberg every 6 hours and mirrors the published Zig `master` release assets from `https://ziglang.org/download/` when upstream changes.

Release artifacts are built from the synced `master` branch source, not from the automation branch.

It republishes the published `master` asset set, including:

- source and bootstrap tarballs
- Windows, macOS, Linux, FreeBSD, NetBSD, and OpenBSD binaries for every architecture currently published in the Zig `master` download index

It publishes two release styles:

- immutable per-commit prereleases such as `upstream-<shortsha>`
- a rolling `latest-master` prerelease with stable asset names for "give me the newest build"

Release assets are mirrored from the official Zig download index rather than rebuilt on GitHub-hosted runners, which avoids upstream CI dependencies that are not publicly downloadable.
