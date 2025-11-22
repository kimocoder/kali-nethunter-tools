#!/bin/bash
# build-zlib.sh - Build zlib for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="zlib"
TOOL_VERSION="1.x"
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

# zlib uses its own configure script
log_cmd ./configure \
  --prefix="$INSTALL_DIR" \
  --static

log "Step 2: Building $TOOL_NAME..."
log_cmd make -j"$PARALLEL_JOBS" \
  CC="$CC" \
  CFLAGS="$CFLAGS" \
  LDFLAGS="$LDFLAGS"

log "Step 3: Installing $TOOL_NAME..."
log_cmd make install

log "Step 4: Verifying installation..."
if [ ! -f "$INSTALL_DIR/lib/libz.a" ]; then
  log "ERROR: libz.a not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
