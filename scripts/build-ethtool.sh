#!/bin/bash
# build-ethtool.sh - Build ethtool for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="ethtool"
TOOL_VERSION="6.15"
TOOL_DEPS=()
TOOL_CONFIGURE_OPTS="--enable-static --disable-shared --enable-pretty-dump"
TOOL_PATCHES=("ethtool-android.patch")

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
if [ -d "$SCRIPT_DIR/../src/ethtool" ]; then
  if [ -d "$SRC_DIR/ethtool-src" ]; then
    log "Removing existing source directory..."
    rm -rf "$SRC_DIR/ethtool-src"
  fi
  log "Copying fresh ethtool source..."
  cp -r "$SCRIPT_DIR/../src/ethtool" "$SRC_DIR/ethtool-src"
else
  log "ERROR: Source directory not found: $SCRIPT_DIR/../src/ethtool"
  exit 1
fi

cd "$SRC_DIR/ethtool-src"

log "Step 2: Applying patches..."

for patch in "${TOOL_PATCHES[@]}"; do
  if [ -f "$SCRIPT_DIR/../patches/$patch" ]; then
    log "Applying patch: $patch"
    # Check if patch is already applied
    if patch -p1 --dry-run -R < "$SCRIPT_DIR/../patches/$patch" > /dev/null 2>&1; then
      log "Patch $patch already applied, skipping..."
    else
      patch -p1 < "$SCRIPT_DIR/../patches/$patch" || {
        log "WARNING: Patch $patch failed to apply (may already be applied)"
      }
    fi
  fi
done

log "Step 3: Running autogen.sh..."

# Run autogen to generate configure script
if [ -f autogen.sh ]; then
  log_cmd ./autogen.sh
elif [ ! -f configure ]; then
  log_cmd autoreconf -fi
fi

log "Step 4: Configuring $TOOL_NAME..."

# Set up pkg-config for libmnl
export PKG_CONFIG_PATH="$PREFIX/libmnl/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export PKG_CONFIG_LIBDIR="$PREFIX/libmnl/lib/pkgconfig"

# Configure with Android toolchain
log_cmd ./configure \
  --host="$TARGET_TRIPLE" \
  --prefix="$INSTALL_DIR" \
  --enable-static \
  --disable-shared \
  --enable-pretty-dump \
  --enable-netlink \
  CC="$CC" \
  CXX="$CXX" \
  CFLAGS="$CFLAGS -D_GNU_SOURCE -I$PREFIX/libmnl/include" \
  CXXFLAGS="$CXXFLAGS -D_GNU_SOURCE -I$PREFIX/libmnl/include" \
  LDFLAGS="$LDFLAGS -static -L$PREFIX/libmnl/lib" \
  MNL_CFLAGS="-I$PREFIX/libmnl/include" \
  MNL_LIBS="-L$PREFIX/libmnl/lib -lmnl"

log "Step 5: Building $TOOL_NAME..."

log_cmd make -j"$PARALLEL_JOBS"

log "Step 6: Installing $TOOL_NAME..."

log_cmd make install

log "Step 7: Fixing TLS alignment for ARM64..."

# Fix TLS alignment for ARM64 binaries
if [ "$TARGET_ARCH" = "arm64" ] || [ "$TARGET_ARCH" = "aarch64" ]; then
  TLS_FIX_SCRIPT="$SCRIPT_DIR/fix-tls-alignment.py"
  if [ -f "$TLS_FIX_SCRIPT" ] && [ -f "$INSTALL_DIR/sbin/ethtool" ]; then
    log "Fixing TLS alignment for ethtool..."
    python3 "$TLS_FIX_SCRIPT" "$INSTALL_DIR/sbin/ethtool" || log "WARNING: TLS fix failed for ethtool"
  fi
fi

log "Step 8: Verifying installation..."

if [ ! -f "$INSTALL_DIR/sbin/ethtool" ]; then
  log "ERROR: ethtool binary not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
