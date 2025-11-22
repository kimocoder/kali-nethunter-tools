#!/bin/bash
# build-libintl-stub.sh - Build libintl stub for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="libintl-stub"
TOOL_DEPS=()

SRC_DIR="$SCRIPT_DIR/../src/libintl-stub"
INSTALL_DIR="$PREFIX/$TOOL_NAME"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$(readlink -f "$LOG_DIR")/build-$TOOL_NAME-$(date +%s).log"

mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/include"

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

log "Building libintl stub..."

cd "$SRC_DIR"

# Compile the stub
log_cmd $CC $CFLAGS -c libintl-stub.c -o libintl-stub.o

# Create static library
log_cmd $AR rcs libintl.a libintl-stub.o

# Install
cp libintl.a "$INSTALL_DIR/lib/"

log "SUCCESS: libintl stub built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
