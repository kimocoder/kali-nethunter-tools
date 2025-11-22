#!/bin/bash
# build-libnl3.sh - Build libnl3 for Android
# This script downloads, configures, and builds libnl3 for cross-compilation to Android

set -euo pipefail

# Source environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

# ============================================================================
# Tool Configuration
# ============================================================================
TOOL_NAME="libnl3"
TOOL_VERSION="3.7.0"
TOOL_DEPS=()  # No dependencies
TOOL_CONFIGURE_OPTS="--disable-cli --disable-pthreads"
TOOL_PATCHES=("libnl-android-in_addr.patch")

# ============================================================================
# Directories
# ============================================================================
BUILD_DIR="$SCRIPT_DIR/build/$TOOL_NAME"
SRC_DIR="$BUILD_DIR/src"
INSTALL_DIR="$PREFIX/$TOOL_NAME"

# Ensure LOG_DIR exists and use absolute path
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$(readlink -f "$LOG_DIR")/build-$TOOL_NAME-$(date +%s).log"

mkdir -p "$BUILD_DIR" "$SRC_DIR" "$INSTALL_DIR"

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
log "Step 1: Using local libnl source..."

# Copy local source to build directory
if [ ! -d "$SRC_DIR/libnl-src" ]; then
  log "Copying local libnl source..."
  if [ -d "$SCRIPT_DIR/../src/libnl" ]; then
    cp -r "$SCRIPT_DIR/../src/libnl" "$SRC_DIR/libnl-src"
  else
    log "ERROR: Source directory not found: $SCRIPT_DIR/../src/libnl"
    exit 1
  fi
fi

cd "$SRC_DIR/libnl-src"

# ============================================================================
# Apply Patches
# ============================================================================
log "Step 2: Applying patches..."

for patch in "${TOOL_PATCHES[@]}"; do
  if [ -f "$SCRIPT_DIR/patches/$patch" ]; then
    log "Applying patch: $patch"
    patch -p1 < "$SCRIPT_DIR/patches/$patch" || log "Patch already applied or failed (continuing)"
  fi
done

# ============================================================================
# Configure
# ============================================================================
log "Step 3: Configuring $TOOL_NAME..."

# Clean previous build
if [ -f Makefile ]; then
  log_cmd make distclean || true
fi

# Generate configure if needed
if [ ! -f configure ]; then
  log "Generating configure script..."
  log_cmd autoreconf -fi || log_cmd ./autogen.sh || true
fi

# Configure with cross-compilation flags
log_cmd ./configure \
  --host="$TARGET_TRIPLE" \
  --prefix="$INSTALL_DIR" \
  $TOOL_CONFIGURE_OPTS \
  CC="$CC" \
  CXX="$CXX" \
  CPPFLAGS="-include netinet/in.h" \
  CFLAGS="$CFLAGS" \
  CXXFLAGS="$CXXFLAGS" \
  LDFLAGS="$LDFLAGS"

# ============================================================================
# Build
# ============================================================================
log "Step 4: Building $TOOL_NAME..."

log_cmd make -j"$PARALLEL_JOBS"

# ============================================================================
# Install
# ============================================================================
log "Step 5: Installing $TOOL_NAME..."

log_cmd make install

# ============================================================================
# Verify Installation
# ============================================================================
log "Step 6: Verifying installation..."

if [ ! -d "$INSTALL_DIR/lib" ]; then
  log "ERROR: lib directory not found in $INSTALL_DIR"
  exit 1
fi

if [ ! -d "$INSTALL_DIR/include" ]; then
  log "ERROR: include directory not found in $INSTALL_DIR"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"

# Create marker file
touch "$INSTALL_DIR/.built"

log "Build log saved to: $LOG_FILE"
