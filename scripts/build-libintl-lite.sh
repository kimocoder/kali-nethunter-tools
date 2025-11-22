#!/bin/bash
# build-libintl-lite.sh - Build libintl-lite for Android
# This script builds libintl-lite for cross-compilation to Android

set -euo pipefail

# Source environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

# ============================================================================
# Tool Configuration
# ============================================================================
TOOL_NAME="libintl-lite"
TOOL_VERSION="1.0"
TOOL_DEPS=()  # No dependencies
TOOL_CONFIGURE_OPTS=""
TOOL_PATCHES=()

# ============================================================================
# Directories
# ============================================================================
BUILD_DIR="$SCRIPT_DIR/build/$TOOL_NAME"
INSTALL_DIR="$PREFIX/$TOOL_NAME"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$(readlink -f "$LOG_DIR")/build-$TOOL_NAME-$(date +%s).log"

mkdir -p "$BUILD_DIR" "$INSTALL_DIR" "$LOG_DIR"

# ============================================================================
# Logging
# ============================================================================
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_cmd() {
  log "Executing: $*"
  "$@" 2>&1 | tee -a "$LOG_FILE" || {
    log "ERROR: Command failed with exit code $?"
    return 1
  }
}

# ============================================================================
# Use Local Source
# ============================================================================
log "Step 1: Using local libintl-lite source..."

LIBINTL_SRC="$SCRIPT_DIR/../src/libintl-lite"

if [ ! -d "$LIBINTL_SRC" ]; then
  log "ERROR: libintl-lite source not found at $LIBINTL_SRC"
  exit 1
fi

# ============================================================================
# Configure
# ============================================================================
log "Step 2: Configuring $TOOL_NAME..."

# Clean and recreate build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Determine CMake Android ABI based on target triple
if [[ "$TARGET_TRIPLE" == aarch64* ]]; then
  CMAKE_ANDROID_ABI="arm64-v8a"
elif [[ "$TARGET_TRIPLE" == armv7a* ]]; then
  CMAKE_ANDROID_ABI="armeabi-v7a"
else
  log "ERROR: Unsupported target triple: $TARGET_TRIPLE"
  exit 1
fi

# Configure with CMake for Android
log_cmd cmake "$LIBINTL_SRC" \
  -DCMAKE_SYSTEM_NAME=Android \
  -DCMAKE_SYSTEM_VERSION="$API_LEVEL" \
  -DCMAKE_ANDROID_ARCH_ABI="$CMAKE_ANDROID_ABI" \
  -DCMAKE_ANDROID_NDK="$ANDROID_NDK" \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$CFLAGS" \
  -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DBUILD_SHARED_LIBS=ON

# ============================================================================
# Build
# ============================================================================
log "Step 3: Building $TOOL_NAME..."

log_cmd make -j"$PARALLEL_JOBS"

# ============================================================================
# Install
# ============================================================================
log "Step 4: Installing $TOOL_NAME..."

log_cmd make install

# ============================================================================
# Build Shared Library
# ============================================================================
log "Step 4.5: Building shared library..."

# Build shared library manually since CMakeLists.txt only builds static
cd "$BUILD_DIR"
log_cmd $CXX $CXXFLAGS -fPIC -shared \
  "$LIBINTL_SRC/internal/libintl.cpp" \
  -o libintl.so

# Install shared library
cp libintl.so "$INSTALL_DIR/lib/"
log "Shared library installed to $INSTALL_DIR/lib/libintl.so"

# ============================================================================
# Verify Installation
# ============================================================================
log "Step 5: Verifying installation..."

if [ ! -d "$INSTALL_DIR/lib" ]; then
  log "ERROR: lib directory not found in $INSTALL_DIR"
  exit 1
fi

if [ ! -f "$INSTALL_DIR/lib/libintl.a" ]; then
  log "ERROR: libintl.a not found in $INSTALL_DIR/lib"
  exit 1
fi

if [ ! -f "$INSTALL_DIR/include/libintl.h" ]; then
  log "ERROR: libintl.h not found in $INSTALL_DIR/include"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"

# Create marker file
touch "$INSTALL_DIR/.built"

log "Build log saved to: $LOG_FILE"
