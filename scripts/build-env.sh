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
# TLS Alignment Fix Function
# ============================================================================
# Fix TLS alignment for Android binaries
# Usage: fix_tls_alignment <binary_path>
fix_tls_alignment() {
  local binary="$1"
  
  if [ ! -f "$binary" ]; then
    echo "WARNING: Binary not found: $binary" >&2
    return 1
  fi
  
  # Determine which fix script to use based on architecture
  local fix_script=""
  if [ "$TARGET_ARCH" = "arm64" ] || [ "$TARGET_ARCH" = "aarch64" ]; then
    fix_script="$SCRIPT_DIR/fix-tls-alignment.py"
    local required_align="64"
  elif [ "$TARGET_ARCH" = "arm" ] || [ "$TARGET_ARCH" = "armv7a" ]; then
    fix_script="$SCRIPT_DIR/fix-tls-alignment-arm32.py"
    local required_align="32"
  else
    echo "WARNING: Unknown architecture for TLS fix: $TARGET_ARCH" >&2
    return 1
  fi
  
  if [ ! -f "$fix_script" ]; then
    echo "WARNING: TLS fix script not found: $fix_script" >&2
    return 1
  fi
  
  # Apply the fix
  python3 "$fix_script" "$binary" 2>&1 || {
    echo "WARNING: TLS alignment fix failed for $binary" >&2
    return 1
  }
  
  return 0
}

# Fix TLS alignment for all binaries in a directory
# Usage: fix_tls_alignment_dir <directory>
fix_tls_alignment_dir() {
  local dir="$1"
  local count=0
  local failed=0
  
  if [ ! -d "$dir" ]; then
    echo "WARNING: Directory not found: $dir" >&2
    return 1
  fi
  
  # Find all ELF binaries in the directory
  while IFS= read -r -d '' binary; do
    if file "$binary" | grep -q "ELF"; then
      if fix_tls_alignment "$binary"; then
        ((count++))
      else
        ((failed++))
      fi
    fi
  done < <(find "$dir" -type f -executable -print0)
  
  if [ $count -gt 0 ]; then
    echo "Fixed TLS alignment for $count binaries in $dir"
  fi
  
  if [ $failed -gt 0 ]; then
    echo "WARNING: Failed to fix TLS alignment for $failed binaries" >&2
  fi
  
  return 0
}

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
