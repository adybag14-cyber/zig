#!/usr/bin/env bash

set -euo pipefail

if (( $# != 3 )); then
  echo "usage: $0 <bootstrap-root> <seed-bootstrap-tarball-url> <required-llvm-major>" >&2
  exit 1
fi

BOOTSTRAP_ROOT="$1"
SEED_TARBALL_URL="$2"
REQUIRED_LLVM_MAJOR="$3"

if [[ ! "$REQUIRED_LLVM_MAJOR" =~ ^[0-9]+$ ]]; then
  echo "required LLVM major must be a number, got: $REQUIRED_LLVM_MAJOR" >&2
  exit 1
fi

read_bootstrap_llvm_major() {
  local root="$1"
  local version_file="$root/cmake/Modules/LLVMVersion.cmake"

  if [[ ! -f "$version_file" ]]; then
    echo "Missing LLVM version file: $version_file" >&2
    return 1
  fi

  sed -nE 's/^ *set\(LLVM_VERSION_MAJOR ([0-9]+)\)$/\1/p' "$version_file" | head -n 1
}

has_compact_unwind_header() {
  local root="$1"
  [[ -f "$root/libunwind/include/mach-o/compact_unwind_encoding.h" ]]
}

work_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

mkdir -p "$BOOTSTRAP_ROOT"
rm -rf "$BOOTSTRAP_ROOT"/*

echo "Downloading bootstrap seed tarball..."
curl -L --fail --retry 3 --retry-delay 2 --output "$work_dir/bootstrap.tar.xz" "$SEED_TARBALL_URL"

tar -xJf "$work_dir/bootstrap.tar.xz" -C "$BOOTSTRAP_ROOT" --strip-components=1

seed_llvm_major="$(read_bootstrap_llvm_major "$BOOTSTRAP_ROOT")"

if [[ "$seed_llvm_major" == "$REQUIRED_LLVM_MAJOR" ]] && has_compact_unwind_header "$BOOTSTRAP_ROOT"; then
  echo "Bootstrap seed already matches required LLVM major ($REQUIRED_LLVM_MAJOR) and includes libunwind Mach-O headers."
  exit 0
fi

if [[ "$seed_llvm_major" != "$REQUIRED_LLVM_MAJOR" ]]; then
  echo "Bootstrap seed LLVM major ($seed_llvm_major) does not match required major ($REQUIRED_LLVM_MAJOR)."
else
  echo "Bootstrap seed is missing libunwind Mach-O headers required by lld."
fi

echo "Overlaying LLVM sources from llvm-project release/$REQUIRED_LLVM_MAJOR.x ..."

llvm_tarball_url="${LLVM_PROJECT_TARBALL_URL:-https://github.com/llvm/llvm-project/archive/refs/heads/release/${REQUIRED_LLVM_MAJOR}.x.tar.gz}"
curl -L --fail --retry 3 --retry-delay 2 --output "$work_dir/llvm-project.tar.gz" "$llvm_tarball_url"

mkdir -p "$work_dir/llvm-project"
tar -xzf "$work_dir/llvm-project.tar.gz" -C "$work_dir/llvm-project"

llvm_src_root="$(printf '%s\n' "$work_dir"/llvm-project/* | head -n 1)"

for src_dir in cmake llvm clang lld libunwind; do
  if [[ ! -d "$llvm_src_root/$src_dir" ]]; then
    echo "Missing expected directory in llvm-project tarball: $src_dir" >&2
    exit 1
  fi

  rm -rf "$BOOTSTRAP_ROOT/$src_dir"
  mv "$llvm_src_root/$src_dir" "$BOOTSTRAP_ROOT/$src_dir"
done

final_llvm_major="$(read_bootstrap_llvm_major "$BOOTSTRAP_ROOT")"

if [[ "$final_llvm_major" != "$REQUIRED_LLVM_MAJOR" ]]; then
  echo "Failed to prepare bootstrap sources with required LLVM major: expected $REQUIRED_LLVM_MAJOR, got $final_llvm_major" >&2
  exit 1
fi

if ! has_compact_unwind_header "$BOOTSTRAP_ROOT"; then
  echo "Failed to prepare libunwind Mach-O compact unwind headers required by lld" >&2
  exit 1
fi

echo "Prepared bootstrap sources with LLVM major $final_llvm_major."
