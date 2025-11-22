#!/bin/bash
# build-macchanger.sh - Build macchanger for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="macchanger"
TOOL_VERSION="1.7.0"
TOOL_DEPS=()
TOOL_CONFIGURE_OPTS="--disable-shared"
TOOL_PATCHES=("macchanger-android.patch")

BUILD_DIR="$SCRIPT_DIR/build/$TOOL_NAME"
SRC_DIR="$BUILD_DIR/src"
INSTALL_DIR="$PREFIX/$TOOL_NAME"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$(readlink -f "$LOG_DIR")/build-$TOOL_NAME-$(date +%s).log"

mkdir -p "$BUILD_DIR" "$SRC_DIR" "$INSTALL_DIR" "$LOG_DIR"

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

log "Step 1: Downloading $TOOL_NAME $TOOL_VERSION..."

MACCHANGER_URL="https://github.com/alobbs/macchanger/archive/refs/tags/1.7.0.tar.gz"
MACCHANGER_ARCHIVE="$BUILD_DIR/macchanger-${TOOL_VERSION}.tar.gz"

if [ ! -f "$MACCHANGER_ARCHIVE" ]; then
  log_cmd wget -c "$MACCHANGER_URL" -O "$MACCHANGER_ARCHIVE"
else
  log "Source archive already exists: $MACCHANGER_ARCHIVE"
fi

if [ ! -d "$SRC_DIR/macchanger-src" ]; then
  log "Extracting $MACCHANGER_ARCHIVE..."
  cd "$SRC_DIR"
  tar xzf "$MACCHANGER_ARCHIVE"
  for dir in macchanger*; do
    if [ -d "$dir" ]; then
      mv "$dir" macchanger-src
      break
    fi
  done
fi

cd "$SRC_DIR/macchanger-src"

log "Step 2: Applying patches..."
for patch in "${TOOL_PATCHES[@]}"; do
  if [ -f "$SCRIPT_DIR/patches/$patch" ]; then
    log "Applying patch: $patch"
    patch -p1 < "$SCRIPT_DIR/patches/$patch" || log "Patch already applied or failed (continuing)"
  fi
done

log "Step 3: Configuring $TOOL_NAME..."

if [ -f Makefile ]; then
  log_cmd make distclean || true
fi

if [ ! -f configure ]; then
  log "Generating configure script..."
  log_cmd autoreconf -fi || true
fi

log_cmd ./configure \
  --host="$TARGET_TRIPLE" \
  --prefix="$INSTALL_DIR" \
  $TOOL_CONFIGURE_OPTS \
  CC="$CC" CXX="$CXX" CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS"

log "Step 4: Building $TOOL_NAME..."
# Only build the src directory, skip documentation
log_cmd make -C src -j"$PARALLEL_JOBS"

log "Step 5: Installing $TOOL_NAME..."
# Manually install the binary since we're skipping make install
mkdir -p "$INSTALL_DIR/bin"
cp src/macchanger "$INSTALL_DIR/bin/"
$STRIP "$INSTALL_DIR/bin/macchanger"

log "Step 6: Verifying installation..."
if [ ! -f "$INSTALL_DIR/bin/macchanger" ]; then
  log "ERROR: macchanger executable not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
