#!/bin/bash
# build-openssl.sh - Build OpenSSL for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="openssl"
TOOL_VERSION="3.x"
TOOL_DEPS=()

BUILD_DIR="$SCRIPT_DIR/build/$TOOL_NAME"
SRC_DIR="$SCRIPT_DIR/../src/libssl"
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

log "Step 1: Configuring $TOOL_NAME..."

cd "$SRC_DIR"

# Clean previous build
make distclean 2>/dev/null || true

# Determine Android architecture target
case "$TARGET_ARCH" in
  aarch64|arm64)
    OPENSSL_TARGET="android-arm64"
    ;;
  armv7a|arm)
    OPENSSL_TARGET="android-arm"
    ;;
  x86_64)
    OPENSSL_TARGET="android-x86_64"
    ;;
  x86)
    OPENSSL_TARGET="android-x86"
    ;;
  *)
    log "ERROR: Unsupported architecture: $TARGET_ARCH"
    exit 1
    ;;
esac

# Set up environment for OpenSSL build
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
export PATH="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"

log_cmd ./Configure $OPENSSL_TARGET \
  -D__ANDROID_API__=21 \
  --prefix="$INSTALL_DIR" \
  --openssldir="$INSTALL_DIR/ssl" \
  no-shared \
  no-tests \
  -Wl,-z,max-page-size=16384 \
  -D_GNU_SOURCE \
  -fno-emulated-tls

log "Step 2: Building $TOOL_NAME..."
log_cmd make -j"$PARALLEL_JOBS"

log "Step 3: Installing $TOOL_NAME..."
log_cmd make install_sw install_ssldirs

log "Step 4: Verifying installation..."
if [ ! -f "$INSTALL_DIR/lib/libssl.a" ] || [ ! -f "$INSTALL_DIR/lib/libcrypto.a" ]; then
  log "ERROR: OpenSSL libraries not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
