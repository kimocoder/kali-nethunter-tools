#!/bin/bash
# build-libgcrypt.sh - Build libgcrypt for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="libgcrypt"
TOOL_VERSION="1.10.3"
TOOL_DEPS=("libgpg-error")

BUILD_DIR="$SCRIPT_DIR/../build/$TOOL_NAME"
SRC_DIR="$BUILD_DIR/src/libgcrypt-src"
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

# Use local source or download if not present
if [ ! -d "$SRC_DIR" ]; then
  mkdir -p "$BUILD_DIR/src"
  # Check for local source first
  if [ -d "$SCRIPT_DIR/../src/libgcrypt" ]; then
    log "Using local libgcrypt source..."
    cp -r "$SCRIPT_DIR/../src/libgcrypt" "$SRC_DIR"
  else
    log "Local source not found, downloading libgcrypt $TOOL_VERSION..."
    cd "$BUILD_DIR"
    GCRYPT_URL="https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-$TOOL_VERSION.tar.bz2"
    log_cmd wget -O libgcrypt-$TOOL_VERSION.tar.bz2 "$GCRYPT_URL"
    log_cmd tar xf libgcrypt-$TOOL_VERSION.tar.bz2
    mv "libgcrypt-$TOOL_VERSION" "$SRC_DIR"
  fi
fi

cd "$SRC_DIR"

log "Step 1: Configuring $TOOL_NAME..."

# Clean previous build
make distclean 2>/dev/null || true

export PKG_CONFIG_PATH="$PREFIX/libgpg-error/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

log_cmd ./configure \
  --host="$TARGET_TRIPLE" \
  --prefix="$INSTALL_DIR" \
  --enable-static \
  --disable-shared \
  --disable-doc \
  --with-libgpg-error-prefix="$PREFIX/libgpg-error" \
  CC="$CC" \
  CXX="$CXX" \
  CFLAGS="${CFLAGS//-fno-emulated-tls/} -I$PREFIX/libgpg-error/include" \
  CXXFLAGS="${CXXFLAGS//-fno-emulated-tls/} -I$PREFIX/libgpg-error/include" \
  LDFLAGS="$LDFLAGS -L$PREFIX/libgpg-error/lib"

log "Step 2: Building $TOOL_NAME..."
log_cmd make -j"$PARALLEL_JOBS"

log "Step 3: Installing $TOOL_NAME..."
log_cmd make install

log "Step 4: Verifying installation..."
if [ ! -f "$INSTALL_DIR/lib/libgcrypt.a" ]; then
  log "ERROR: libgcrypt.a not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
