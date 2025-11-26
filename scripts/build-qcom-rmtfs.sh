#!/bin/bash
# build-qcom-rmtfs.sh - Build Qualcomm Remote Filesystem Service for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="qcom-rmtfs"
TOOL_VERSION="master"
TOOL_DEPS=("libqrtr")
TOOL_PATCHES=("qcom-rmtfs-android.patch")

BUILD_DIR="$SCRIPT_DIR/../build/$TOOL_NAME"
SRC_DIR="$BUILD_DIR/src/rmtfs-src"
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

log "Verifying dependencies..."
for dep in "${TOOL_DEPS[@]}"; do
  if [ ! -f "$PREFIX/$dep/.built" ]; then
    log "ERROR: Dependency $dep not built"
    exit 1
  fi
done

log "Step 1: Preparing $TOOL_NAME source..."

# Check for local source
if [ -d "$SCRIPT_DIR/../src/qcom-rmtfs" ] && [ ! -d "$SRC_DIR" ]; then
  log "Using local qcom-rmtfs source..."
  mkdir -p "$BUILD_DIR/src"
  cp -r "$SCRIPT_DIR/../src/qcom-rmtfs" "$SRC_DIR"
else
  log "Using existing source in $SRC_DIR"
fi

cd "$SRC_DIR"

log "Step 2: Applying patches..."
for patch in "${TOOL_PATCHES[@]}"; do
  if [ -f "$SCRIPT_DIR/../patches/$patch" ]; then
    log "Applying patch: $patch"
    patch -p1 < "$SCRIPT_DIR/../patches/$patch" || log "Patch already applied or failed (continuing)"
  fi
done

log "Step 3: Building $TOOL_NAME..."

# Clean previous build
if [ -f Makefile ]; then
  log "Cleaning previous build..."
  make clean 2>/dev/null || true
fi

# Note: rmtfs requires libqrtr and libpthread
# libudev is disabled for Android via patch
log "Building with Android-specific patches (udev disabled)..."

# Build with custom flags (disable udev for Android)
# Note: pthread is built into Android's libc, no need to link separately
log_cmd make \
  CC="$CC" \
  CFLAGS="$CFLAGS -I$PREFIX/libqrtr/include -DANDROID" \
  LDFLAGS="$LDFLAGS -L$PREFIX/libqrtr/lib -lqrtr" \
  prefix="$INSTALL_DIR" \
  -j"$PARALLEL_JOBS" || {
    log "ERROR: Build failed. This tool requires:"
    log "  - libqrtr (Qualcomm IPC Router library)"
    log "  - libudev (device management library - not available on Android)"
    log "  - libpthread (POSIX threads library)"
    exit 1
  }

log "Step 4: Installing $TOOL_NAME..."

# Install manually since the Makefile install might not work for cross-compilation
mkdir -p "$INSTALL_DIR/bin"
if [ -f rmtfs ]; then
  cp -v rmtfs "$INSTALL_DIR/bin/"
else
  log "ERROR: rmtfs binary not found after build"
  exit 1
fi

log "Step 5: Verifying installation..."
if [ ! -f "$INSTALL_DIR/bin/rmtfs" ]; then
  log "ERROR: rmtfs binary not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
