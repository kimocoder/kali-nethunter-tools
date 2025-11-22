#!/bin/bash
# build-hcxdumptool.sh - Build hcxdumptool for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="hcxdumptool"
TOOL_VERSION="7.0.1"
TOOL_DEPS=("libpcap" "openssl" "ifaddrs")
TOOL_CONFIGURE_OPTS=""
TOOL_PATCHES=("hcxdumptool-android.patch")

BUILD_DIR="$SCRIPT_DIR/build/$TOOL_NAME"
SRC_DIR="$SCRIPT_DIR/../src/$TOOL_NAME"
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

log "Verifying dependencies..."
for dep in "${TOOL_DEPS[@]}"; do
  if [ ! -f "$PREFIX/$dep/.built" ]; then
    log "ERROR: Dependency $dep not built"
    exit 1
  fi
done

log "Step 1: Using git source from $SRC_DIR..."

if [ ! -d "$SRC_DIR" ]; then
  log "ERROR: Source directory not found: $SRC_DIR"
  log "Please run: git clone https://github.com/ZerBea/hcxdumptool src/hcxdumptool"
  exit 1
fi

cd "$SRC_DIR"

log "Step 2: Applying patches..."
for patch in "${TOOL_PATCHES[@]}"; do
  if [ -f "$SCRIPT_DIR/patches/$patch" ]; then
    log "Applying patch: $patch"
    patch -p1 < "$SCRIPT_DIR/patches/$patch" || log "Patch already applied or failed (continuing)"
  fi
done

log "Step 3: Patching for Android..."

# Replace the ifaddrs include paths
sed -i 's|include/android-ifaddrs/ifaddrs.h|ifaddrs.h|g' hcxdumptool.c
sed -i 's|include/android-ifaddrs/ifaddrs.c|ifaddrs.h|g' hcxdumptool.c

log "Step 4: Building $TOOL_NAME..."

mkdir -p "$INSTALL_DIR/bin"

# Clean previous build
make clean 2>/dev/null || true

log_cmd make \
  CC="$CC" \
  CFLAGS="$CFLAGS -I$PREFIX/libpcap/include -I$PREFIX/openssl/include -I$PREFIX/ifaddrs/include" \
  LDFLAGS="-static -L$PREFIX/libpcap/lib -L$PREFIX/openssl/lib -L$PREFIX/ifaddrs/lib -lpcap -lssl -lcrypto -lifaddrs -ldl -Wl,-z,max-page-size=16384" \
  -j"$PARALLEL_JOBS"

log "Step 5: Installing $TOOL_NAME..."

if [ -x "hcxdumptool" ]; then
  log_cmd cp hcxdumptool "$INSTALL_DIR/bin/"
  # Fix TLS alignment for Android (ARM requires 32, ARM64 requires 64)
  if [ "$TARGET_ARCH" = "arm64" ]; then
    TLS_ALIGN=64
  else
    TLS_ALIGN=32
  fi
  log "Fixing TLS alignment to $TLS_ALIGN..."
  python3 "$SCRIPT_DIR/fix-tls-alignment.py" "$INSTALL_DIR/bin/hcxdumptool" $TLS_ALIGN 2>&1 | tee -a "$LOG_FILE" || log "WARNING: TLS alignment fix failed"
  log_cmd "$STRIP" "$INSTALL_DIR/bin/hcxdumptool"
fi

log "Step 6: Verifying installation..."
if [ ! -f "$INSTALL_DIR/bin/hcxdumptool" ]; then
  log "ERROR: hcxdumptool executable not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
