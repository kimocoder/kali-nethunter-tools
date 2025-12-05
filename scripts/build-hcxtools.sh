#!/bin/bash
# build-hcxtools.sh - Build hcxtools for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="hcxtools"
TOOL_VERSION="7.0.1"
TOOL_DEPS=("libpcap" "openssl")
TOOL_CONFIGURE_OPTS=""
TOOL_PATCHES=("hcxtools-android.patch")

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
  log "Please run: git clone https://github.com/ZerBea/hcxtools src/hcxtools"
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

log "Step 3: Building $TOOL_NAME..."

mkdir -p "$INSTALL_DIR/bin"

# Override pkg-config to prevent finding system libraries
export PKG_CONFIG_PATH="$PREFIX/openssl/lib/pkgconfig:$PREFIX/libpcap/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PREFIX/openssl/lib/pkgconfig:$PREFIX/libpcap/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

# Patch Makefile to remove pthread and add zlib
sed -i 's/-lpthread//g' Makefile
sed -i 's/$(Z_LIBS)/-lz/g' Makefile

# Only build tools that don't require curl
# Remove tools that need curl: hcxhashtool, wlancap2wpasec, whoismac
TOOLS_TO_BUILD="hcxpcapngtool hcxpsktool hcxpmktool hcxeiutool hcxwltool hcxhash2cap"

log_cmd make \
  CC="$CC" \
  CFLAGS="$CFLAGS -I$PREFIX/libpcap/include -I$PREFIX/openssl/include -I$PREFIX/zlib/include -fno-emulated-tls" \
  LDFLAGS="$LDFLAGS -static -L$PREFIX/libpcap/lib -L$PREFIX/openssl/lib -L$PREFIX/zlib/lib -lz -ldl -Wl,-z,max-page-size=16384" \
  PKG_CONFIG="pkg-config" \
  $TOOLS_TO_BUILD \
  -j"$PARALLEL_JOBS"

log "Step 4: Installing $TOOL_NAME..."

for binary in hcx*; do
  if [ -x "$binary" ] && [ -f "$binary" ] && [[ ! "$binary" =~ \.(c|h|o)$ ]]; then
    log_cmd cp "$binary" "$INSTALL_DIR/bin/"
    # Fix TLS alignment for Android
    log "Fixing TLS alignment for $binary..."
    fix_tls_alignment "$INSTALL_DIR/bin/$binary" || log "WARNING: TLS alignment fix failed for $binary"
    log_cmd "$STRIP" "$INSTALL_DIR/bin/$binary"
  fi
done

log "Step 5: Verifying installation..."
if [ ! -d "$INSTALL_DIR/bin" ] || [ -z "$(ls -A $INSTALL_DIR/bin)" ]; then
  log "ERROR: No binaries installed"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
