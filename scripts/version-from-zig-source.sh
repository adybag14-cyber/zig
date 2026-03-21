#!/usr/bin/env bash

set -euo pipefail

src_dir="${1:-.}"
cmake_file="$src_dir/CMakeLists.txt"

read_version_component() {
  local key="$1"
  sed -nE "s/^set\\(${key} ([0-9]+)\\)$/\\1/p" "$cmake_file" | head -n 1
}

major="$(read_version_component ZIG_VERSION_MAJOR)"
minor="$(read_version_component ZIG_VERSION_MINOR)"
patch="$(read_version_component ZIG_VERSION_PATCH)"

if [[ -z "$major" || -z "$minor" || -z "$patch" ]]; then
  echo "Failed to read Zig version components from $cmake_file" >&2
  exit 1
fi

base_version="${major}.${minor}.${patch}"
git_describe="$(git -C "$src_dir" describe --match '*.*.*' --tags --abbrev=9)"

if [[ "$git_describe" =~ ^v?([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  echo "$base_version"
  exit 0
fi

if [[ "$git_describe" =~ ^v?([0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)-g([0-9a-f]+)$ ]]; then
  echo "${base_version}-dev.${BASH_REMATCH[2]}+${BASH_REMATCH[3]}"
  exit 0
fi

echo "Failed to derive Zig version from git describe output: $git_describe" >&2
exit 1
