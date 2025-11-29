#!/bin/bash
# build-iw.sh - Build iw (wireless configuration tool) for Android
# This script downloads, configures, and builds iw for cross-compilation to Android
# Depends on: libnl3

set -euo pipefail

# Source environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

# ============================================================================
# Tool Configuration
# ============================================================================
TOOL_NAME="iw"
TOOL_VERSION="5.16"
TOOL_DEPS=("libnl3")  # Dependencies
TOOL_CONFIGURE_OPTS="--disable-cli"
TOOL_PATCHES=("iw-android.patch")

# ============================================================================
# Verify Dependencies
# ============================================================================
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Verifying dependencies for $TOOL_NAME..."

for dep in "${TOOL_DEPS[@]}"; do
  DEP_DIR="$PREFIX/$dep"
  if [ ! -f "$DEP_DIR/.built" ]; then
    log "ERROR: Dependency $dep not built. Please build it first."
    exit 1
  fi
  log "Dependency $dep found at $DEP_DIR"
done

# ============================================================================
# Directories
# ============================================================================
BUILD_DIR="$SCRIPT_DIR/build/$TOOL_NAME"
SRC_DIR="$BUILD_DIR/src"
INSTALL_DIR="$PREFIX/$TOOL_NAME"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$(readlink -f "$LOG_DIR")/build-$TOOL_NAME-$(date +%s).log"

mkdir -p "$BUILD_DIR" "$SRC_DIR" "$INSTALL_DIR" "$LOG_DIR"

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
log "Step 1: Using local iw source..."

# Copy local source to build directory
if [ ! -d "$SRC_DIR/iw-src" ]; then
  log "Copying local iw source..."
  cp -r "$SCRIPT_DIR/../src/iw" "$SRC_DIR/iw-src"
fi

cd "$SRC_DIR/iw-src"

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
# Build (iw uses make, not autotools)
# ============================================================================
log "Step 3: Building $TOOL_NAME..."

# Set up pkg-config path for dependencies
export PKG_CONFIG_PATH="$PREFIX/libnl3/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

# Build with cross-compilation flags (static)
log_cmd make \
  CC="$CC" \
  CFLAGS="$CFLAGS -I$PREFIX/libnl3/include" \
  LDFLAGS="$LDFLAGS -static -L$PREFIX/libnl3/lib" \
  LIBS="-ldl" \
  -j"$PARALLEL_JOBS"

# ============================================================================
# Install
# ============================================================================
log "Step 4: Installing $TOOL_NAME..."

# Create install directories
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/include"
mkdir -p "$INSTALL_DIR/lib"

# Copy binary
if [ -f iw ]; then
  log_cmd cp iw "$INSTALL_DIR/bin/"
  log_cmd "$STRIP" "$INSTALL_DIR/bin/iw"
else
  log "ERROR: iw binary not found after build"
  exit 1
fi

# ============================================================================
# Fix TLS Alignment
# ============================================================================
log "Step 5: Fixing TLS alignment..."

if [ -f "$INSTALL_DIR/bin/iw" ]; then
  fix_tls_alignment "$INSTALL_DIR/bin/iw" || log "WARNING: TLS alignment fix failed for iw"
fi

# ============================================================================
# Verify Installation
# ============================================================================
log "Step 6: Verifying installation..."

if [ ! -f "$INSTALL_DIR/bin/iw" ]; then
  log "ERROR: iw executable not found in $INSTALL_DIR/bin"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"

# Create marker file
touch "$INSTALL_DIR/.built"

log "Build log saved to: $LOG_FILE"
