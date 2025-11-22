#!/bin/bash
# build-nmap.sh - Build nmap for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="nmap"
TOOL_VERSION="7.93"
TOOL_DEPS=()
TOOL_CONFIGURE_OPTS="--disable-shared"
TOOL_PATCHES=("nmap-android.patch")

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

log "Step 1: Preparing $TOOL_NAME source..."

# Check for local source first
if [ -d "$SCRIPT_DIR/../src/nmap" ] && [ ! -d "$SRC_DIR/nmap-src" ]; then
  log "Using local nmap source..."
  cp -r "$SCRIPT_DIR/../src/nmap" "$SRC_DIR/nmap-src"
elif [ ! -d "$SRC_DIR/nmap-src" ]; then
  log "Local source not found, downloading $TOOL_NAME $TOOL_VERSION..."
  NMAP_URL="https://nmap.org/dist/nmap-${TOOL_VERSION}.tar.bz2"
  NMAP_ARCHIVE="$BUILD_DIR/nmap-${TOOL_VERSION}.tar.bz2"
  
  if [ ! -f "$NMAP_ARCHIVE" ]; then
    log_cmd wget -c "$NMAP_URL" -O "$NMAP_ARCHIVE"
  else
    log "Source archive already exists: $NMAP_ARCHIVE"
  fi
  
  log "Extracting $NMAP_ARCHIVE..."
  cd "$SRC_DIR"
  tar xjf "$NMAP_ARCHIVE"
  for dir in nmap*; do
    if [ -d "$dir" ]; then
      mv "$dir" nmap-src
      break
    fi
  done
else
  log "Using existing source in $SRC_DIR/nmap-src"
fi

cd "$SRC_DIR/nmap-src"

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
log_cmd make -j"$PARALLEL_JOBS"

log "Step 5: Installing $TOOL_NAME..."
log_cmd make install

log "Step 6: Verifying installation..."
if [ ! -f "$INSTALL_DIR/bin/nmap" ]; then
  log "ERROR: nmap executable not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
