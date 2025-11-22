#!/bin/bash
# build-pcre2.sh - Build PCRE2 for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="pcre2"
TOOL_VERSION="10.x"
TOOL_DEPS=()

BUILD_DIR="$SCRIPT_DIR/../build/$TOOL_NAME"
SRC_DIR="$SCRIPT_DIR/../src/$TOOL_NAME"
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

if [ ! -d "$SRC_DIR" ]; then
  log "ERROR: Source directory not found: $SRC_DIR"
  exit 1
fi

log "Step 1: Configuring $TOOL_NAME..."

cd "$SRC_DIR"

# Clean previous build
make distclean 2>/dev/null || true

# Generate configure if needed
if [ ! -f configure ]; then
  log "Generating configure script..."
  log_cmd autoreconf -fi
fi

log_cmd ./configure \
  --host="$TARGET_TRIPLE" \
  --prefix="$INSTALL_DIR" \
  --enable-static \
  --disable-shared \
  --enable-pcre2-8 \
  --enable-pcre2-16 \
  --enable-pcre2-32 \
  CC="$CC" \
  CXX="$CXX" \
  CFLAGS="$CFLAGS" \
  CXXFLAGS="$CXXFLAGS" \
  LDFLAGS="$LDFLAGS"

log "Step 2: Building $TOOL_NAME..."
log_cmd make -j"$PARALLEL_JOBS"

log "Step 3: Installing $TOOL_NAME..."
log_cmd make install

log "Step 4: Verifying installation..."
if [ ! -f "$INSTALL_DIR/lib/libpcre2-8.a" ]; then
  log "ERROR: libpcre2-8.a not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
