#!/usr/bin/env bash

set -euo pipefail

if (( $# < 4 )); then
  echo "usage: $0 <bootstrap-root> <zig-version> <asset-dir> <target> [<target> ...]" >&2
  echo "       $0 <bootstrap-root> <zig-version> <asset-dir> --host-only" >&2
  exit 1
fi

ROOTDIR="$(cd "$1" && pwd)"
ZIG_VERSION="$2"
ASSET_DIR="$3"
shift 3

HOST_ONLY=0
if [[ "${1:-}" == "--host-only" ]]; then
  if (( $# != 1 )); then
    echo "--host-only cannot be combined with release targets" >&2
    exit 1
  fi
  HOST_ONLY=1
fi

mkdir -p "$ASSET_DIR"
ASSET_DIR="$(cd "$ASSET_DIR" && pwd)"

MCPU="${MCPU:-baseline}"
HOST_MCPU="${HOST_MCPU:-baseline}"
BUILD_JOBS="${BUILD_JOBS:-4}"
HOST_PREFIX="$ROOTDIR/out/host"
HOST_ZIG="$HOST_PREFIX/bin/zig"

cmake_build() {
  cmake --build . --parallel "$BUILD_JOBS" --target install
}

target_os_cmake_name() {
  local target="$1"
  local target_os_and_abi="${target#*-}"
  local target_os="${target_os_and_abi%-*}"

  case "$target_os" in
    macos*) echo "Darwin" ;;
    freebsd*) echo "FreeBSD" ;;
    netbsd*) echo "NetBSD" ;;
    openbsd*) echo "OpenBSD" ;;
    windows*) echo "Windows" ;;
    linux*) echo "Linux" ;;
    native) echo "" ;;
    *)
      echo "Unsupported target OS in $target" >&2
      exit 1
      ;;
  esac
}

asset_basename() {
  case "$1" in
    x86_64-linux-musl) echo "zig-x86_64-linux" ;;
    aarch64-linux-musl) echo "zig-aarch64-linux" ;;
    x86_64-windows-gnu) echo "zig-x86_64-windows" ;;
    aarch64-windows-gnu) echo "zig-aarch64-windows" ;;
    x86_64-macos-none) echo "zig-x86_64-macos" ;;
    aarch64-macos-none) echo "zig-aarch64-macos" ;;
    *)
      echo "Unsupported release target $1" >&2
      exit 1
      ;;
  esac
}

package_target() {
  local target="$1"
  local zig_prefix="$2"
  local package_base
  local package_dir

  package_base="$(asset_basename "$target")"
  package_dir="$ROOTDIR/out/package/${package_base}-${ZIG_VERSION}"

  rm -rf "$package_dir"
  mkdir -p "$package_dir"
  cp -a "$zig_prefix/." "$package_dir/"

  if [[ "$target" == *windows* ]]; then
    (
      cd "$ROOTDIR/out/package"
      zip -qr "$ASSET_DIR/${package_base}-${ZIG_VERSION}.zip" "$(basename "$package_dir")"
    )
  else
    (
      cd "$ROOTDIR/out/package"
      tar -cJf "$ASSET_DIR/${package_base}-${ZIG_VERSION}.tar.xz" "$(basename "$package_dir")"
    )
  fi

  rm -rf "$package_dir"
}

build_host_toolchain() {
  mkdir -p "$ROOTDIR/out/build-llvm-host"
  cd "$ROOTDIR/out/build-llvm-host"
  cmake "$ROOTDIR/llvm" \
    -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$HOST_PREFIX" \
    -DCMAKE_PREFIX_PATH="$HOST_PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_APPEND_VC_REV=OFF \
    -DLLVM_ENABLE_BINDINGS=OFF \
    -DLLVM_ENABLE_LIBEDIT=OFF \
    -DLLVM_ENABLE_LIBPFM=OFF \
    -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_ENABLE_OCAMLDOC=OFF \
    -DLLVM_ENABLE_PLUGINS=OFF \
    -DLLVM_ENABLE_PROJECTS="lld;clang" \
    -DLLVM_ENABLE_Z3_SOLVER=OFF \
    -DLLVM_ENABLE_ZSTD=OFF \
    -DLLVM_INCLUDE_UTILS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_PARALLEL_LINK_JOBS=1 \
    -DLLVM_TOOL_LLVM_LTO2_BUILD=OFF \
    -DLLVM_TOOL_LLVM_LTO_BUILD=OFF \
    -DLLVM_TOOL_LTO_BUILD=OFF \
    -DLLVM_TOOL_REMARKS_SHLIB_BUILD=OFF \
    -DCLANG_ENABLE_ARCMT=OFF \
    -DCLANG_BUILD_TOOLS=OFF \
    -DCLANG_INCLUDE_DOCS=OFF \
    -DCLANG_INCLUDE_TESTS=OFF \
    -DCLANG_TOOL_CLANG_IMPORT_TEST_BUILD=OFF \
    -DCLANG_TOOL_CLANG_LINKER_WRAPPER_BUILD=OFF \
    -DCLANG_TOOL_C_INDEX_TEST_BUILD=OFF \
    -DCLANG_TOOL_LIBCLANG_BUILD=OFF
  cmake_build

  mkdir -p "$ROOTDIR/out/build-zig-host"
  cd "$ROOTDIR/out/build-zig-host"
  cmake "$ROOTDIR/zig" \
    -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$HOST_PREFIX" \
    -DCMAKE_PREFIX_PATH="$HOST_PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DZIG_TARGET_MCPU="$HOST_MCPU" \
    -DZIG_VERSION="$ZIG_VERSION"
  cmake_build
}

build_zstd_for_target() {
  local target="$1"
  local prefix="$2"
  local static_zstd="$prefix/lib/libzstd.a"

  mkdir -p "$prefix/include" "$prefix/lib"
  cp "$ROOTDIR/zstd/lib/zstd.h" "$prefix/include/zstd.h"
  cd "$prefix/lib"
  "$HOST_ZIG" build-lib \
    --name zstd \
    -target "$target" \
    -mcpu="$MCPU" \
    -fno-sanitize-c \
    -fstrip \
    -OReleaseFast \
    -lc \
    "$ROOTDIR/zstd/lib/decompress/zstd_ddict.c" \
    "$ROOTDIR/zstd/lib/decompress/zstd_decompress.c" \
    "$ROOTDIR/zstd/lib/decompress/huf_decompress.c" \
    "$ROOTDIR/zstd/lib/decompress/huf_decompress_amd64.S" \
    "$ROOTDIR/zstd/lib/decompress/zstd_decompress_block.c" \
    "$ROOTDIR/zstd/lib/compress/zstdmt_compress.c" \
    "$ROOTDIR/zstd/lib/compress/zstd_opt.c" \
    "$ROOTDIR/zstd/lib/compress/hist.c" \
    "$ROOTDIR/zstd/lib/compress/zstd_ldm.c" \
    "$ROOTDIR/zstd/lib/compress/zstd_fast.c" \
    "$ROOTDIR/zstd/lib/compress/zstd_compress_literals.c" \
    "$ROOTDIR/zstd/lib/compress/zstd_double_fast.c" \
    "$ROOTDIR/zstd/lib/compress/huf_compress.c" \
    "$ROOTDIR/zstd/lib/compress/fse_compress.c" \
    "$ROOTDIR/zstd/lib/compress/zstd_lazy.c" \
    "$ROOTDIR/zstd/lib/compress/zstd_compress.c" \
    "$ROOTDIR/zstd/lib/compress/zstd_compress_sequences.c" \
    "$ROOTDIR/zstd/lib/compress/zstd_compress_superblock.c" \
    "$ROOTDIR/zstd/lib/deprecated/zbuff_compress.c" \
    "$ROOTDIR/zstd/lib/deprecated/zbuff_decompress.c" \
    "$ROOTDIR/zstd/lib/deprecated/zbuff_common.c" \
    "$ROOTDIR/zstd/lib/common/entropy_common.c" \
    "$ROOTDIR/zstd/lib/common/pool.c" \
    "$ROOTDIR/zstd/lib/common/threading.c" \
    "$ROOTDIR/zstd/lib/common/zstd_common.c" \
    "$ROOTDIR/zstd/lib/common/xxhash.c" \
    "$ROOTDIR/zstd/lib/common/debug.c" \
    "$ROOTDIR/zstd/lib/common/fse_decompress.c" \
    "$ROOTDIR/zstd/lib/common/error_private.c" \
    "$ROOTDIR/zstd/lib/dictBuilder/zdict.c" \
    "$ROOTDIR/zstd/lib/dictBuilder/divsufsort.c" \
    "$ROOTDIR/zstd/lib/dictBuilder/fastcover.c" \
    "$ROOTDIR/zstd/lib/dictBuilder/cover.c"

  if [[ "$target" == *windows-gnu && ! -f "$static_zstd" ]]; then
    if [[ -f "$prefix/lib/zstd.lib" ]]; then
      cp "$prefix/lib/zstd.lib" "$static_zstd"
    elif [[ -f "$prefix/lib/libzstd.lib" ]]; then
      cp "$prefix/lib/libzstd.lib" "$static_zstd"
    fi
  fi

  if [[ ! -f "$static_zstd" ]]; then
    echo "Expected static zstd archive at $static_zstd" >&2
    find "$prefix/lib" -maxdepth 1 -type f -printf '  %f\n' >&2
    exit 1
  fi
}

build_target() {
  local target="$1"
  local cmake_os_name
  local prefix="$ROOTDIR/out/${target}-${MCPU}"
  local zig_prefix="$ROOTDIR/out/zig-${target}-${MCPU}"
  local llvm_cmake_extra_args=()
  local llvm_build_static=ON
  local llvm_enable_pic=OFF

  cmake_os_name="$(target_os_cmake_name "$target")"

  if [[ "$target" == *-macos-* ]]; then
    llvm_build_static=OFF
    llvm_enable_pic=ON

    # LLVM's zlib probe links a try-compile executable; Darwin cross builds can
    # fail that probe even though the static libz archive was just built.
    llvm_cmake_extra_args+=(-DHAVE_ZLIB=1)
    # CheckAtomic uses the same cross-link shape and can incorrectly conclude
    # that Darwin targets need libatomic, which they do not.
    llvm_cmake_extra_args+=(
      -DHAVE_CXX_ATOMICS_WITHOUT_LIB=1
      -DHAVE_CXX_ATOMICS64_WITHOUT_LIB=1
      -DLLVM_HAS_ATOMICS=1
    )
    # Darwin provides these, but CMake's cross-link probes can fail before
    # LLVM writes the config header used by Support/Unix/Process.inc.
    llvm_cmake_extra_args+=(
      -DHAVE_GETPAGESIZE=1
      -DHAVE_SYSCONF=1
      -DHAVE_GETRUSAGE=1
    )
    # Darwin has pthread rwlocks through libSystem; avoid LLVM's target
    # try-link fallback path, which leaves RWMutex.cpp without MutexImpl.
    llvm_cmake_extra_args+=(
      -DHAVE_PTHREAD_H=1
      -DHAVE_PTHREAD_RWLOCK_INIT=1
    )
  fi

  mkdir -p "$ROOTDIR/out/build-zlib-${target}-${MCPU}"
  cd "$ROOTDIR/out/build-zlib-${target}-${MCPU}"
  cmake "$ROOTDIR/zlib" \
    -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_PREFIX_PATH="$prefix" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CROSSCOMPILING=True \
    -DCMAKE_SYSTEM_NAME="$cmake_os_name" \
    -DCMAKE_C_COMPILER="$HOST_ZIG;cc;-fno-sanitize=all;-s;-target;$target;-mcpu=$MCPU" \
    -DCMAKE_CXX_COMPILER="$HOST_ZIG;c++;-fno-sanitize=all;-s;-target;$target;-mcpu=$MCPU" \
    -DCMAKE_ASM_COMPILER="$HOST_ZIG;cc;-fno-sanitize=all;-s;-target;$target;-mcpu=$MCPU" \
    -DCMAKE_LINK_DEPENDS_USE_LINKER=OFF \
    -DCMAKE_RC_COMPILER="$HOST_PREFIX/bin/llvm-rc" \
    -DCMAKE_AR="$HOST_PREFIX/bin/llvm-ar" \
    -DCMAKE_RANLIB="$HOST_PREFIX/bin/llvm-ranlib"
  cmake_build

  build_zstd_for_target "$target" "$prefix"

  mkdir -p "$ROOTDIR/out/build-llvm-${target}-${MCPU}"
  cd "$ROOTDIR/out/build-llvm-${target}-${MCPU}"
  cmake "$ROOTDIR/llvm" \
    -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_PREFIX_PATH="$prefix" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CROSSCOMPILING=True \
    -DCMAKE_SYSTEM_NAME="$cmake_os_name" \
    -DCMAKE_C_COMPILER="$HOST_ZIG;cc;-fno-sanitize=all;-s;-target;$target;-mcpu=$MCPU" \
    -DCMAKE_CXX_COMPILER="$HOST_ZIG;c++;-fno-sanitize=all;-s;-target;$target;-mcpu=$MCPU" \
    -DCMAKE_ASM_COMPILER="$HOST_ZIG;cc;-fno-sanitize=all;-s;-target;$target;-mcpu=$MCPU" \
    -DCMAKE_LINK_DEPENDS_USE_LINKER=OFF \
    -DCMAKE_RC_COMPILER="$HOST_PREFIX/bin/llvm-rc" \
    -DCMAKE_AR="$HOST_PREFIX/bin/llvm-ar" \
    -DCMAKE_RANLIB="$HOST_PREFIX/bin/llvm-ranlib" \
    -DLLVM_FORCE_USE_OLD_TOOLCHAIN=ON \
    -DLLVM_APPEND_VC_REV=OFF \
    -DLLVM_ENABLE_PIC="$llvm_enable_pic" \
    -DLLVM_ENABLE_BACKTRACES=OFF \
    -DLLVM_ENABLE_BINDINGS=OFF \
    -DLLVM_ENABLE_CRASH_OVERRIDES=OFF \
    -DLLVM_ENABLE_LIBEDIT=OFF \
    -DLLVM_ENABLE_LIBPFM=OFF \
    -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_ENABLE_OCAMLDOC=OFF \
    -DLLVM_ENABLE_PLUGINS=OFF \
    -DLLVM_ENABLE_PROJECTS="lld;clang" \
    -DLLVM_ENABLE_Z3_SOLVER=OFF \
    -DLLVM_ENABLE_ZLIB=FORCE_ON \
    "${llvm_cmake_extra_args[@]}" \
    -DLLVM_ENABLE_ZSTD=FORCE_ON \
    -DLLVM_USE_STATIC_ZSTD=ON \
    -DLLVM_TABLEGEN="$HOST_PREFIX/bin/llvm-tblgen" \
    -DLLVM_BUILD_UTILS=OFF \
    -DLLVM_BUILD_TOOLS=OFF \
    -DLLVM_BUILD_STATIC="$llvm_build_static" \
    -DLLVM_INCLUDE_UTILS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_DEFAULT_TARGET_TRIPLE="$target" \
    -DLLVM_PARALLEL_LINK_JOBS=1 \
    -DLLVM_TOOL_LLVM_LTO2_BUILD=OFF \
    -DLLVM_TOOL_LLVM_LTO_BUILD=OFF \
    -DLLVM_TOOL_LTO_BUILD=OFF \
    -DLLVM_TOOL_REMARKS_SHLIB_BUILD=OFF \
    -DCLANG_TABLEGEN="$ROOTDIR/out/build-llvm-host/bin/clang-tblgen" \
    -DCLANG_ENABLE_ARCMT=OFF \
    -DCLANG_BUILD_TOOLS=OFF \
    -DCLANG_INCLUDE_DOCS=OFF \
    -DCLANG_INCLUDE_TESTS=OFF \
    -DCLANG_ENABLE_OBJC_REWRITER=ON \
    -DCLANG_TOOL_CLANG_IMPORT_TEST_BUILD=OFF \
    -DCLANG_TOOL_CLANG_LINKER_WRAPPER_BUILD=OFF \
    -DCLANG_TOOL_C_INDEX_TEST_BUILD=OFF \
    -DCLANG_TOOL_LIBCLANG_BUILD=OFF \
    -DLLD_BUILD_TOOLS=OFF
  cmake_build

  cd "$ROOTDIR/zig"
  "$HOST_ZIG" build \
    --prefix "$zig_prefix" \
    --search-prefix "$prefix" \
    -Dflat \
    -Dstatic-llvm \
    -Doptimize=ReleaseFast \
    -Dstrip \
    -Dtarget="$target" \
    -Dcpu="$MCPU" \
    -Dversion-string="$ZIG_VERSION"

  package_target "$target" "$zig_prefix"

  rm -rf "$ROOTDIR/out/build-zlib-${target}-${MCPU}"
  rm -rf "$ROOTDIR/out/build-llvm-${target}-${MCPU}"
  rm -rf "$prefix"
  rm -rf "$zig_prefix"
}

mkdir -p "$ROOTDIR/out/package"

if [[ ! -x "$HOST_ZIG" ]]; then
  build_host_toolchain
fi

if (( HOST_ONLY )); then
  exit 0
fi

for target in "$@"; do
  build_target "$target"
done
