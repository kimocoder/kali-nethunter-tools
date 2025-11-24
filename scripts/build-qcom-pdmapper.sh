#!/bin/bash
# build-qcom-pdmapper.sh - Build Qualcomm PD Mapper for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="qcom-pdmapper"
TOOL_VERSION="master"
TOOL_DEPS=()
TOOL_CONFIGURE_OPTS=""
TOOL_PATCHES=()

# Note: This tool requires libqrtr (Qualcomm IPC Router) and liblzma
# These are typically available on Qualcomm-based Android devices

BUILD_DIR="$SCRIPT_DIR/../build/$TOOL_NAME"
SRC_DIR="$BUILD_DIR/src/pdmapper-src"
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
if [ -d "$SCRIPT_DIR/../src/qcom-pdmapper" ] && [ ! -d "$SRC_DIR" ]; then
  log "Using local qcom-pdmapper source..."
  mkdir -p "$BUILD_DIR/src"
  cp -r "$SCRIPT_DIR/../src/qcom-pdmapper" "$SRC_DIR"
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

# Check for required libraries
log "Checking for required libraries..."
if ! pkg-config --exists libqrtr 2>/dev/null; then
  log "WARNING: libqrtr not found via pkg-config"
  log "This tool requires libqrtr (Qualcomm IPC Router library)"
  log "Attempting to build anyway - may fail if libraries are not available"
fi

# Build with custom flags
# Note: pd-mapper requires libqrtr and liblzma
# These should be available on target Qualcomm devices
log_cmd make \
  CC="$CC" \
  CFLAGS="$CFLAGS -I$SYSROOT/usr/include" \
  LDFLAGS="$LDFLAGS -lqrtr -llzma" \
  -j"$PARALLEL_JOBS" || {
    log "ERROR: Build failed. This tool requires:"
    log "  - libqrtr (Qualcomm IPC Router library)"
    log "  - liblzma (XZ Utils library)"
    log "These libraries must be available for the target platform"
    exit 1
  }

log "Step 4: Installing $TOOL_NAME..."

# Install manually since the Makefile install might not work for cross-compilation
mkdir -p "$INSTALL_DIR/bin"
cp -v pd-mapper "$INSTALL_DIR/bin/"

log "Step 5: Verifying installation..."
if [ ! -f "$INSTALL_DIR/bin/pd-mapper" ]; then
  log "ERROR: pd-mapper binary not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
