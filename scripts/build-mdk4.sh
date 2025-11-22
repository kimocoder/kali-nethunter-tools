#!/bin/bash
# build-mdk4.sh - Build mdk4 (WiFi testing tool) for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="mdk4"
TOOL_VERSION="master"
TOOL_DEPS=("libpcap" "libnl3")
TOOL_CONFIGURE_OPTS=""

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

log "Verifying dependencies..."
for dep in "${TOOL_DEPS[@]}"; do
  if [ ! -f "$PREFIX/$dep/.built" ]; then
    log "ERROR: Dependency $dep not built"
    exit 1
  fi
done

if [ ! -d "$SRC_DIR" ]; then
  log "ERROR: Source directory not found: $SRC_DIR"
  exit 1
fi

log "Step 1: Configuring $TOOL_NAME..."

cd "$SRC_DIR"

# Clean previous build
make clean 2>/dev/null || true

log "Step 2: Patching for Android..."

# Rename mdk4's pcap.h to avoid conflict with libpcap's pcap.h
if [ -f src/pcap.h ] && [ ! -f src/pcap_defs.h ]; then
  log "Renaming src/pcap.h to src/pcap_defs.h to avoid header conflict"
  mv src/pcap.h src/pcap_defs.h
  # Update the include in osdep/file.c
  sed -i 's/#include "pcap\.h"/#include "pcap_defs.h"/' src/osdep/file.c
fi

log "Step 3: Building $TOOL_NAME..."

# Export build variables for mdk4
export CC="$CC"
export CFLAGS="$CFLAGS -I$PREFIX/libpcap/include -I$PREFIX/libnl3/include/libnl3 -fcommon"
export LDFLAGS="$LDFLAGS -static -L$PREFIX/libpcap/lib -L$PREFIX/libnl3/lib"
# Remove pthread dependency for Android
export LINKFLAGS="-lpcap -lnl-genl-3 -lnl-3 -lm -ldl"

# Patch src/Makefile to remove pthread
sed -i 's/-lpthread//g' src/Makefile

# Build mdk4
log_cmd make -j"$PARALLEL_JOBS"

log "Step 4: Installing $TOOL_NAME..."
mkdir -p "$INSTALL_DIR/bin"
cp src/mdk4 "$INSTALL_DIR/bin/"
$STRIP "$INSTALL_DIR/bin/mdk4"

log "Step 5: Verifying installation..."
if [ ! -f "$INSTALL_DIR/bin/mdk4" ]; then
  log "ERROR: mdk4 executable not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
