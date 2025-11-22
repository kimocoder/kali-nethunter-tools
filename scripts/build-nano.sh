#!/bin/bash
# build-nano.sh - Build nano text editor for Android
# This script downloads, configures, and builds nano for cross-compilation to Android

set -euo pipefail

# Source environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

# ============================================================================
# Tool Configuration
# ============================================================================
TOOL_NAME="nano"
TOOL_VERSION="8.2"
TOOL_DEPS=("ncurses")
TOOL_CONFIGURE_OPTS="--disable-nls"
TOOL_PATCHES=("nano-android.patch")

# ============================================================================
# Directories
# ============================================================================
BUILD_DIR="$SCRIPT_DIR/build/$TOOL_NAME"
SRC_DIR="$SCRIPT_DIR/../src/$TOOL_NAME"
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
log "Step 1: Using nano source from $SRC_DIR..."

if [ ! -d "$SRC_DIR" ]; then
  log "ERROR: Source directory not found: $SRC_DIR"
  log "Please download nano source to src/nano"
  exit 1
fi

cd "$SRC_DIR"

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

# Generate build files if needed
if [ ! -f Makefile.in ]; then
  log "Generating build files..."
  log_cmd ./autogen.sh
fi

# Configure with cross-compilation flags
# Set ac_cv_lib_tinfo_tgetent=no to prevent linking with tinfo (doesn't exist on Android)
log_cmd ./configure \
  --host="$TARGET_TRIPLE" \
  --prefix="$INSTALL_DIR" \
  $TOOL_CONFIGURE_OPTS \
  --disable-doc \
  ac_cv_lib_tinfo_tgetent=no \
  CC="$CC" \
  CXX="$CXX" \
  CFLAGS="$CFLAGS -I$PREFIX/ncurses/include -I$PREFIX/ncurses/include/ncursesw" \
  CXXFLAGS="$CXXFLAGS -I$PREFIX/ncurses/include -I$PREFIX/ncurses/include/ncursesw" \
  LDFLAGS="$LDFLAGS -static -L$PREFIX/ncurses/lib" \
  LIBS="-lncursesw"

# Remove -ltinfo from Makefiles (tinfo doesn't exist on Android)
log "Removing -ltinfo references from Makefiles..."
find . -name Makefile -exec sed -i 's/-ltinfo//g' {} \;

# ============================================================================
# Build
# ============================================================================
log "Step 4: Building $TOOL_NAME..."

# Build lib first, then src
log_cmd make -j"$PARALLEL_JOBS" -C lib
log_cmd make -j"$PARALLEL_JOBS" -C src

# ============================================================================
# Install
# ============================================================================
log "Step 5: Installing $TOOL_NAME..."

# Install manually
mkdir -p "$INSTALL_DIR/bin"
cp src/nano "$INSTALL_DIR/bin/"
"$STRIP" "$INSTALL_DIR/bin/nano"

# ============================================================================
# Verify Installation
# ============================================================================
log "Step 6: Verifying installation..."

if [ ! -f "$INSTALL_DIR/bin/nano" ]; then
  log "ERROR: nano executable not found in $INSTALL_DIR/bin"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"

# Create marker file
touch "$INSTALL_DIR/.built"

log "Build log saved to: $LOG_FILE"
