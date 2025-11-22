#!/bin/bash
# build-libpcap.sh - Build libpcap for Android
# This script downloads, configures, and builds libpcap for cross-compilation to Android

set -euo pipefail

# Source environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

# ============================================================================
# Tool Configuration
# ============================================================================
TOOL_NAME="libpcap"
TOOL_VERSION="1.10.1"
TOOL_DEPS=()  # No dependencies
TOOL_CONFIGURE_OPTS="--disable-shared"
TOOL_PATCHES=("libpcap-android.patch")

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
# Download Source
# ============================================================================
log "Step 1: Preparing $TOOL_NAME source..."

# Check for local source first
if [ -d "$SCRIPT_DIR/../src/libpcap" ] && [ ! -d "$SRC_DIR/libpcap-src" ]; then
  log "Using local libpcap source..."
  cp -r "$SCRIPT_DIR/../src/libpcap" "$SRC_DIR/libpcap-src"
elif [ ! -d "$SRC_DIR/libpcap-src" ]; then
  log "Local source not found, downloading $TOOL_NAME $TOOL_VERSION..."
  LIBPCAP_URL="https://github.com/the-tcpdump-group/libpcap/archive/refs/tags/libpcap-1.10.1.tar.gz"
  LIBPCAP_ARCHIVE="$BUILD_DIR/libpcap-1.10.1.tar.gz"
  
  if [ ! -f "$LIBPCAP_ARCHIVE" ]; then
    log_cmd wget -c "$LIBPCAP_URL" -O "$LIBPCAP_ARCHIVE"
  else
    log "Source archive already exists: $LIBPCAP_ARCHIVE"
  fi
  
  log "Extracting $LIBPCAP_ARCHIVE..."
  cd "$SRC_DIR"
  tar xzf "$LIBPCAP_ARCHIVE"
  
  # Find and rename the extracted directory
  for dir in libpcap*; do
    if [ -d "$dir" ]; then
      mv "$dir" libpcap-src
      break
    fi
  done
else
  log "Using existing source in $SRC_DIR/libpcap-src"
fi

cd "$SRC_DIR/libpcap-src"

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
  --without-libnl \
  CC="$CC" \
  CXX="$CXX" \
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
