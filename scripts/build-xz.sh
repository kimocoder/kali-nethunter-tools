#!/bin/bash
# build-xz.sh - Build XZ Utils (provides liblzma) for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="xz"
TOOL_VERSION="5.6.3"
TOOL_DEPS=()
TOOL_PATCHES=("xz-android.patch")

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

log "Step 1: Preparing build directory..."

# Copy source to build directory to avoid polluting source
if [ ! -d "$BUILD_DIR/xz-src" ]; then
  log "Copying source to build directory..."
  mkdir -p "$BUILD_DIR"
  cp -r "$SRC_DIR" "$BUILD_DIR/xz-src"
fi

cd "$BUILD_DIR/xz-src"

# Apply patches
log "Step 2: Applying patches..."
for patch in "${TOOL_PATCHES[@]}"; do
  if [ -f "$SCRIPT_DIR/../patches/$patch" ]; then
    log "Applying patch: $patch"
    patch -p1 < "$SCRIPT_DIR/../patches/$patch" || log "Patch already applied or failed (continuing)"
  fi
done

# Generate configure script if needed
if [ ! -f configure ]; then
  log "Generating configure script..."
  # Skip po4a (translation tool) to avoid dependency issues
  log_cmd ./autogen.sh --no-po4a
fi

log "Step 3: Configuring $TOOL_NAME..."

log_cmd ./configure \
  --host="$TARGET_TRIPLE" \
  --prefix="$INSTALL_DIR" \
  --enable-static \
  --disable-shared \
  --disable-xz \
  --disable-xzdec \
  --disable-lzmadec \
  --disable-lzmainfo \
  --disable-scripts \
  --disable-doc \
  CC="$CC" \
  CFLAGS="$CFLAGS" \
  LDFLAGS="$LDFLAGS"

log "Step 4: Building $TOOL_NAME..."
log_cmd make -j"$PARALLEL_JOBS"

log "Step 5: Installing $TOOL_NAME..."
log_cmd make install

log "Step 6: Verifying installation..."
if [ ! -f "$INSTALL_DIR/lib/liblzma.a" ]; then
  log "ERROR: liblzma.a not found"
  exit 1
fi

if [ ! -f "$INSTALL_DIR/include/lzma.h" ]; then
  log "ERROR: lzma.h not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
