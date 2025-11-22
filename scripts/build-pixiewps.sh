#!/bin/bash
# build-pixiewps.sh - Build pixiewps (WPS cracking tool) for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="pixiewps"
TOOL_VERSION="1.4.2"
TOOL_DEPS=()
TOOL_CONFIGURE_OPTS="--disable-shared"
TOOL_PATCHES=("pixiewps-android.patch")

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

PIXIEWPS_URL="https://github.com/wiire-a/pixiewps/archive/refs/tags/v1.4.2.tar.gz"
PIXIEWPS_ARCHIVE="$BUILD_DIR/pixiewps-${TOOL_VERSION}.tar.gz"

if [ ! -f "$PIXIEWPS_ARCHIVE" ]; then
  log_cmd wget -c "$PIXIEWPS_URL" -O "$PIXIEWPS_ARCHIVE"
else
  log "Source archive already exists: $PIXIEWPS_ARCHIVE"
fi

if [ ! -d "$SRC_DIR/pixiewps-src" ]; then
  log "Extracting $PIXIEWPS_ARCHIVE..."
  cd "$SRC_DIR"
  tar xzf "$PIXIEWPS_ARCHIVE"
  for dir in pixiewps*; do
    if [ -d "$dir" ]; then
      mv "$dir" pixiewps-src
      break
    fi
  done
fi

cd "$SRC_DIR/pixiewps-src"

log "Step 2: Applying patches..."
for patch in "${TOOL_PATCHES[@]}"; do
  if [ -f "$SCRIPT_DIR/patches/$patch" ]; then
    log "Applying patch: $patch"
    patch -p1 < "$SCRIPT_DIR/patches/$patch" || log "Patch already applied or failed (continuing)"
  fi
done

log "Step 3: Building $TOOL_NAME..."

# pixiewps uses a simple Makefile
# Remove pthread dependency for Android
sed -i 's/-lpthread//' Makefile

log_cmd make \
  CC="$CC" \
  CFLAGS="$CFLAGS" \
  LDFLAGS="$LDFLAGS" \
  -j"$PARALLEL_JOBS"

log "Step 4: Installing $TOOL_NAME..."
mkdir -p "$INSTALL_DIR/bin"
cp pixiewps "$INSTALL_DIR/bin/"
"$STRIP" "$INSTALL_DIR/bin/pixiewps"

log "Step 5: Verifying installation..."
if [ ! -f "$INSTALL_DIR/bin/pixiewps" ]; then
  log "ERROR: pixiewps executable not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
