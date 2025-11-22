#!/bin/bash
# build-env.sh - Environment Configuration for Android Cross-Compilation
# This script defines all cross-compilation environment variables and toolchain configuration
# Source this script in all tool build scripts

set -euo pipefail

# ============================================================================
# NDK Configuration
# ============================================================================
: "${ANDROID_NDK_HOME:?Please set ANDROID_NDK_HOME environment variable}"

ANDROID_NDK="$ANDROID_NDK_HOME"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# Target Configuration
# ============================================================================
# Read from build.conf if available, otherwise use defaults
if [ -f "$SCRIPT_DIR/../build.conf" ]; then
  source "$SCRIPT_DIR/../build.conf"
elif [ -f "$SCRIPT_DIR/build.conf" ]; then
  source "$SCRIPT_DIR/build.conf"
fi

TARGET_ARCH="${TARGET_ARCH:-arm64}"
TARGET_TRIPLE="${TARGET_TRIPLE:-aarch64-linux-android}"
API_LEVEL="${API_LEVEL:-29}"

# ============================================================================
# NDK Paths
# ============================================================================
SYSROOT="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
TOOLCHAIN_BIN="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"

# Validate NDK paths exist
if [ ! -d "$SYSROOT" ]; then
  echo "ERROR: Sysroot not found at $SYSROOT" >&2
  exit 1
fi

if [ ! -d "$TOOLCHAIN_BIN" ]; then
  echo "ERROR: Toolchain bin not found at $TOOLCHAIN_BIN" >&2
  exit 1
fi

# ============================================================================
# Toolchain Binaries
# ============================================================================
export CC="${TOOLCHAIN_BIN}/${TARGET_TRIPLE}${API_LEVEL}-clang"
export CXX="${TOOLCHAIN_BIN}/${TARGET_TRIPLE}${API_LEVEL}-clang++"
export AR="${TOOLCHAIN_BIN}/llvm-ar"
export LD="${TOOLCHAIN_BIN}/ld.lld"
export AS="$CC"
export RANLIB="${TOOLCHAIN_BIN}/llvm-ranlib"
export STRIP="${TOOLCHAIN_BIN}/llvm-strip"

# Validate toolchain binaries exist
for tool in CC CXX AR LD RANLIB STRIP; do
  tool_path="${!tool}"
  if [ ! -x "$tool_path" ]; then
    echo "ERROR: Toolchain binary not found or not executable: $tool_path" >&2
    exit 1
  fi
done

# ============================================================================
# Compiler Flags
# ============================================================================
export CFLAGS="${CFLAGS:---sysroot=$SYSROOT -fPIC -O2 -D_GNU_SOURCE -fno-emulated-tls}"
export CXXFLAGS="${CXXFLAGS:---sysroot=$SYSROOT -fPIC -O2 -D_GNU_SOURCE -fno-emulated-tls}"
export LDFLAGS="${LDFLAGS:---sysroot=$SYSROOT -Wl,-z,max-page-size=16384}"

# ============================================================================
# Output Directory
# ============================================================================
PREFIX="${PREFIX:-$(pwd)/out/${TARGET_TRIPLE}}"
export PREFIX

# Create prefix directory if it doesn't exist
mkdir -p "$PREFIX"

# ============================================================================
# Build Configuration
# ============================================================================
export PARALLEL_JOBS="${PARALLEL_JOBS:-$(nproc)}"
export VERBOSE="${VERBOSE:-0}"
export KEEP_SOURCES="${KEEP_SOURCES:-1}"
export KEEP_BUILD_DIRS="${KEEP_BUILD_DIRS:-0}"
export LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"

mkdir -p "$LOG_DIR" 2>/dev/null || true

# ============================================================================
# Export Summary (for debugging)
# ============================================================================
if [ "${VERBOSE:-0}" = "1" ]; then
  echo "=== Build Environment Configuration ==="
  echo "NDK Home: $ANDROID_NDK"
  echo "Target Triple: $TARGET_TRIPLE"
  echo "API Level: $API_LEVEL"
  echo "Sysroot: $SYSROOT"
  echo "CC: $CC"
  echo "CXX: $CXX"
  echo "AR: $AR"
  echo "LD: $LD"
  echo "RANLIB: $RANLIB"
  echo "STRIP: $STRIP"
  echo "CFLAGS: $CFLAGS"
  echo "LDFLAGS: $LDFLAGS"
  echo "PREFIX: $PREFIX"
  echo "========================================"
fi
