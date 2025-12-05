#!/bin/bash
# build-cowpatty.sh - Build cowpatty (WPA-PSK dictionary attack tool) for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="cowpatty"
TOOL_VERSION="4.8"
TOOL_DEPS=("libpcap" "openssl")
TOOL_CONFIGURE_OPTS=""
TOOL_PATCHES=()

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

log "Step 1: Using source from $SRC_DIR..."

if [ ! -d "$SRC_DIR" ]; then
  log "ERROR: Source directory not found: $SRC_DIR"
  exit 1
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
make clean 2>&1 | tee -a "$LOG_FILE" || true

# Build cowpatty with Android toolchain
log_cmd make \
  CC="$CC" \
  CFLAGS="$CFLAGS -I$PREFIX/libpcap/include -I$PREFIX/openssl/include -DOPENSSL -fno-emulated-tls" \
  LDFLAGS="$LDFLAGS -static -L$PREFIX/libpcap/lib -L$PREFIX/openssl/lib -Wl,-z,max-page-size=16384" \
  LDLIBS="$PREFIX/libpcap/lib/libpcap.a $PREFIX/openssl/lib/libcrypto.a -lz -ldl" \
  -j"$PARALLEL_JOBS"

log "Step 4: Installing $TOOL_NAME..."
mkdir -p "$INSTALL_DIR/bin"

# Fix TLS alignment for Android (ARM requires 32, ARM64 requires 64)
if [ "$TARGET_ARCH" = "arm64" ]; then
  TLS_ALIGN=64
else
  TLS_ALIGN=32
fi

# Install cowpatty and genpmk binaries
for binary in cowpatty genpmk; do
  if [ -f "$binary" ] && [ -x "$binary" ]; then
    log_cmd cp "$binary" "$INSTALL_DIR/bin/"
    # Fix TLS alignment for Android
    log "Fixing TLS alignment for $binary to $TLS_ALIGN..."
    python3 "$SCRIPT_DIR/fix-tls-alignment.py" "$INSTALL_DIR/bin/$binary" $TLS_ALIGN 2>&1 | tee -a "$LOG_FILE" || log "WARNING: TLS alignment fix failed for $binary"
    log_cmd "$STRIP" "$INSTALL_DIR/bin/$binary"
  fi
done

log "Step 5: Verifying installation..."
if [ ! -f "$INSTALL_DIR/bin/cowpatty" ]; then
  log "ERROR: cowpatty executable not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
