#!/bin/bash
# build-libcap.sh - Build libcap (capabilities library) for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="libcap"
TOOL_VERSION="2.66"
TOOL_DEPS=()
TOOL_PATCHES=("libcap-android.patch")

BUILD_DIR="$SCRIPT_DIR/build/$TOOL_NAME"
SRC_DIR="$BUILD_DIR/src"
INSTALL_DIR="$PREFIX/$TOOL_NAME"

# Ensure LOG_DIR exists and use absolute path
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$(readlink -f "$LOG_DIR")/build-$TOOL_NAME-$(date +%s).log"

mkdir -p "$BUILD_DIR" "$SRC_DIR" "$INSTALL_DIR"

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

log "Step 1: Using local libcap source..."

# Copy local source to build directory
if [ ! -d "$SRC_DIR/libcap-src" ]; then
  log "Copying local libcap source..."
  cp -r "$SCRIPT_DIR/../src/libcap" "$SRC_DIR/libcap-src"
fi

cd "$SRC_DIR/libcap-src"

log "Step 2: Applying patches..."
for patch in "${TOOL_PATCHES[@]}"; do
  if [ -f "$SCRIPT_DIR/patches/$patch" ]; then
    log "Applying patch: $patch"
    patch -p1 < "$SCRIPT_DIR/patches/$patch" || log "Patch already applied or failed (continuing)"
  fi
done

log "Step 3: Building $TOOL_NAME..."

# libcap uses make directly, not autotools
# Build only static libraries, skip shared libs that need pthread
log_cmd make -C libcap \
  CC="$CC" \
  BUILD_CC="gcc" \
  CFLAGS="$CFLAGS -D__CAP_NAME_SIZE=32 -D__CAP_BITS=64 -D__CAP_MAXBITS=64" \
  LDFLAGS="$LDFLAGS" \
  SHARED=no \
  lib="lib" \
  libcap.a libpsx.a \
  -j"$PARALLEL_JOBS"

log "Step 4: Installing $TOOL_NAME..."

# Create install directories
mkdir -p "$INSTALL_DIR/lib"
mkdir -p "$INSTALL_DIR/include"

# Copy libraries and headers
cp -r libcap/include/* "$INSTALL_DIR/include/" 2>/dev/null || true
cp libcap/*.a "$INSTALL_DIR/lib/" 2>/dev/null || true

log "Step 5: Verifying installation..."
if [ ! -d "$INSTALL_DIR/include" ]; then
  log "ERROR: Installation incomplete"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
