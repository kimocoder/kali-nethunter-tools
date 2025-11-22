#!/bin/bash
# build-ifaddrs.sh - Build ifaddrs library for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="ifaddrs"
TOOL_VERSION="master"
TOOL_DEPS=()

BUILD_DIR="$SCRIPT_DIR/build/$TOOL_NAME"
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

log "Step 1: Building $TOOL_NAME..."

cd "$SRC_DIR"

# Build ifaddrs as a static library
log "Compiling ifaddrs.c..."
$CC $CFLAGS -c ifaddrs.c -o "$BUILD_DIR/ifaddrs.o"

log "Creating static library..."
$AR rcs "$BUILD_DIR/libifaddrs.a" "$BUILD_DIR/ifaddrs.o"

log "Step 2: Installing $TOOL_NAME..."
mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/include"
cp "$BUILD_DIR/libifaddrs.a" "$INSTALL_DIR/lib/"
cp ifaddrs.h "$INSTALL_DIR/include/"

log "Step 3: Verifying installation..."
if [ ! -f "$INSTALL_DIR/lib/libifaddrs.a" ]; then
  log "ERROR: libifaddrs.a not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
