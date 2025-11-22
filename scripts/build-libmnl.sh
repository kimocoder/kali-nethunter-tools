#!/bin/bash
# build-libmnl.sh - Build libmnl (minimalistic netlink library) for Android

set -euo pipefail

# Source environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

# ============================================================================
# Tool Configuration
# ============================================================================
TOOL_NAME="libmnl"
TOOL_VERSION="1.0.5"
TOOL_DEPS=()
TOOL_PATCHES=()

# ============================================================================
# Directories
# ============================================================================
SRC_DIR="$SCRIPT_DIR/../src/$TOOL_NAME"
INSTALL_DIR="$PREFIX/$TOOL_NAME"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$(readlink -f "$LOG_DIR")/build-$TOOL_NAME-$(date +%s).log"

mkdir -p "$INSTALL_DIR" "$LOG_DIR"

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
log "Step 1: Using libmnl source from $SRC_DIR..."

if [ ! -d "$SRC_DIR" ]; then
  log "ERROR: Source directory not found: $SRC_DIR"
  log "Please ensure libmnl source is in src/libmnl"
  exit 1
fi

cd "$SRC_DIR"

# ============================================================================
# Configure
# ============================================================================
log "Step 2: Configuring $TOOL_NAME..."

# Clean previous build
if [ -f Makefile ]; then
  log_cmd make clean || true
fi

# Run autogen if needed
if [ ! -f configure ]; then
  log "Running autogen.sh..."
  log_cmd ./autogen.sh
fi

# Configure for Android
log_cmd ./configure \
  --host="$TARGET_TRIPLE" \
  --prefix="$INSTALL_DIR" \
  --enable-static \
  --disable-shared \
  CC="$CC" \
  AR="$AR" \
  RANLIB="$RANLIB" \
  CFLAGS="$CFLAGS" \
  LDFLAGS="$LDFLAGS"

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
# Verify Installation
# ============================================================================
log "Step 5: Verifying installation..."

if [ ! -f "$INSTALL_DIR/lib/libmnl.a" ]; then
  log "ERROR: libmnl.a not found in $INSTALL_DIR/lib"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
log "Installed files:"
ls -lh "$INSTALL_DIR/lib/" | tee -a "$LOG_FILE"

# Create marker file
touch "$INSTALL_DIR/.built"

log "Build log saved to: $LOG_FILE"
