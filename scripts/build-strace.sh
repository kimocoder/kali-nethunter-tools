#!/bin/bash
# build-strace.sh - Build strace for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="strace"
TOOL_VERSION="6.12"
TOOL_DEPS=()
TOOL_CONFIGURE_OPTS=""
TOOL_PATCHES=("strace-android-in_addr_t.patch")

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

log "Step 1: Using strace source from $SRC_DIR..."

if [ ! -d "$SRC_DIR" ]; then
  log "ERROR: Source directory not found: $SRC_DIR"
  log "Please ensure strace source is in src/strace"
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

log "Step 3: Generating configure script..."

# Generate configure if needed
if [ ! -f configure ]; then
  log "Running bootstrap..."
  log_cmd ./bootstrap
fi

log "Step 4: Configuring $TOOL_NAME..."

# Clean previous build
if [ -f Makefile ]; then
  log_cmd make distclean || true
fi

log_cmd ./configure \
  --host="$TARGET_TRIPLE" \
  --prefix="$INSTALL_DIR" \
  --enable-mpers=no \
  CC="$CC" \
  CFLAGS="$CFLAGS -Wno-error" \
  LDFLAGS="$LDFLAGS -static"

log "Step 5: Building $TOOL_NAME..."

log_cmd make -j"$PARALLEL_JOBS"

log "Step 6: Installing $TOOL_NAME..."

mkdir -p "$INSTALL_DIR/bin"

if [ -x "src/strace" ]; then
  log_cmd cp src/strace "$INSTALL_DIR/bin/"
  log_cmd "$STRIP" "$INSTALL_DIR/bin/strace"
fi

log "Step 7: Verifying installation..."
if [ ! -f "$INSTALL_DIR/bin/strace" ]; then
  log "ERROR: strace executable not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
