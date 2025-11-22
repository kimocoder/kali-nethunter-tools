#!/bin/bash
# build-rfkill.sh - Build rfkill for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="rfkill"
TOOL_VERSION="1.0"
TOOL_DEPS=()
TOOL_CONFIGURE_OPTS=""
TOOL_PATCHES=()

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

log "Step 1: Using rfkill source from $SRC_DIR..."

if [ ! -d "$SRC_DIR" ]; then
  log "ERROR: Source directory not found: $SRC_DIR"
  log "Please ensure rfkill source is in src/rfkill"
  exit 1
fi

cd "$SRC_DIR"

log "Step 2: Applying patches..."
for patch in "${TOOL_PATCHES[@]}"; do
  if [ -f "$SCRIPT_DIR/patches/$patch" ]; then
    log "Applying patch: $patch"
    patch -p1 < "$SCRIPT_DIR/patches/$patch" || log "Patch already applied or failed (continuing)"
  fi
done

log "Step 3: Building $TOOL_NAME..."

# Clean previous build
make clean 2>/dev/null || true

log_cmd make \
  CC="$CC" \
  CFLAGS="$CFLAGS" \
  LDFLAGS="$LDFLAGS -static" \
  -j"$PARALLEL_JOBS"

log "Step 4: Installing $TOOL_NAME..."

mkdir -p "$INSTALL_DIR/bin"

if [ -x "rfkill" ]; then
  log_cmd cp rfkill "$INSTALL_DIR/bin/"
  log_cmd "$STRIP" "$INSTALL_DIR/bin/rfkill"
fi

log "Step 5: Verifying installation..."
if [ ! -f "$INSTALL_DIR/bin/rfkill" ]; then
  log "ERROR: rfkill executable not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
