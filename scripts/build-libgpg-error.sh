#!/bin/bash
# build-libgpg-error.sh - Build libgpg-error for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="libgpg-error"
TOOL_VERSION="1.47"
TOOL_DEPS=()

BUILD_DIR="$SCRIPT_DIR/../build/$TOOL_NAME"
SRC_DIR="$BUILD_DIR/src/libgpg-error-src"
INSTALL_DIR="$PREFIX/$TOOL_NAME"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$(readlink -f "$LOG_DIR")/build-$TOOL_NAME-$(date +%s).log"

mkdir -p "$BUILD_DIR" "$INSTALL_DIR" "$LOG_DIR"

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

# Use local source or download if not present
if [ ! -d "$SRC_DIR" ]; then
  mkdir -p "$BUILD_DIR/src"
  # Check for local source first
  if [ -d "$SCRIPT_DIR/../src/libgpg-error" ]; then
    log "Using local libgpg-error source..."
    cp -r "$SCRIPT_DIR/../src/libgpg-error" "$SRC_DIR"
  else
    log "Local source not found, downloading libgpg-error $TOOL_VERSION..."
    cd "$BUILD_DIR"
    GPG_ERROR_URL="https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-$TOOL_VERSION.tar.bz2"
    log_cmd wget -O libgpg-error-$TOOL_VERSION.tar.bz2 "$GPG_ERROR_URL"
    log_cmd tar xf libgpg-error-$TOOL_VERSION.tar.bz2
    mv "libgpg-error-$TOOL_VERSION" "$SRC_DIR"
  fi
fi

cd "$SRC_DIR"

log "Step 1: Creating Android lock object files..."

# Create missing lock object files for Android
# mkheader looks for shortened triplet names like "linux-androideabi"
# We need to create these from the existing arm-unknown-linux-androideabi.h
if [ ! -f "src/syscfg/lock-obj-pub.linux-androideabi.h" ]; then
  if [ -f "src/syscfg/lock-obj-pub.arm-unknown-linux-androideabi.h" ]; then
    log "Creating lock-obj-pub.linux-androideabi.h from arm-unknown-linux-androideabi.h"
    cp src/syscfg/lock-obj-pub.arm-unknown-linux-androideabi.h src/syscfg/lock-obj-pub.linux-androideabi.h
  fi
fi

# Also create for aarch64 if needed
if [ ! -f "src/syscfg/lock-obj-pub.linux-android.h" ]; then
  if [ -f "src/syscfg/lock-obj-pub.aarch64-unknown-linux-gnu.h" ]; then
    log "Creating lock-obj-pub.linux-android.h from aarch64-unknown-linux-gnu.h"
    cp src/syscfg/lock-obj-pub.aarch64-unknown-linux-gnu.h src/syscfg/lock-obj-pub.linux-android.h
  fi
fi

log "Step 2: Configuring $TOOL_NAME..."

# Clean previous build
make distclean 2>/dev/null || true

log_cmd ./configure \
  --host="$TARGET_TRIPLE" \
  --prefix="$INSTALL_DIR" \
  --enable-static \
  --disable-shared \
  --disable-nls \
  --disable-doc \
  CC="$CC" \
  CXX="$CXX" \
  CFLAGS="$CFLAGS" \
  CXXFLAGS="$CXXFLAGS" \
  LDFLAGS="$LDFLAGS"

log "Step 3: Building $TOOL_NAME..."
log_cmd make -j"$PARALLEL_JOBS"

log "Step 4: Installing $TOOL_NAME..."
log_cmd make install

log "Step 5: Verifying installation..."
if [ ! -f "$INSTALL_DIR/lib/libgpg-error.a" ]; then
  log "ERROR: libgpg-error.a not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
