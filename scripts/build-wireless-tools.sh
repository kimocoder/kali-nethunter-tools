#!/bin/bash
# build-wireless-tools.sh - Build wireless-tools for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="wireless-tools"
TOOL_VERSION="30.pre9"
TOOL_DEPS=()
TOOL_CONFIGURE_OPTS=""
TOOL_PATCHES=("wireless-tools-android.patch")

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
if [ -d "$SCRIPT_DIR/../src/wireless-tools" ]; then
  if [ -d "$SRC_DIR/wireless-tools-src" ]; then
    log "Removing existing source directory..."
    rm -rf "$SRC_DIR/wireless-tools-src"
  fi
  log "Copying fresh wireless-tools source..."
  cp -r "$SCRIPT_DIR/../src/wireless-tools" "$SRC_DIR/wireless-tools-src"
else
  log "ERROR: Source directory not found: $SCRIPT_DIR/../src/wireless-tools"
  exit 1
fi

cd "$SRC_DIR/wireless-tools-src"

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

log "Step 3: Building $TOOL_NAME..."

# Build with Android toolchain
log_cmd make \
  CC="$CC" \
  AR="$AR" \
  RANLIB="$RANLIB" \
  CFLAGS="$CFLAGS -D_GNU_SOURCE -I." \
  LDFLAGS="$LDFLAGS -static" \
  BUILD_STATIC=y \
  PREFIX="$INSTALL_DIR" \
  -j"$PARALLEL_JOBS"

log "Step 4: Installing $TOOL_NAME..."

mkdir -p "$INSTALL_DIR/sbin" "$INSTALL_DIR/lib" "$INSTALL_DIR/include"

# Install binaries
for prog in iwconfig iwlist iwpriv iwspy iwgetid iwevent ifrename; do
  if [ -f "$prog" ]; then
    log "Installing $prog..."
    cp "$prog" "$INSTALL_DIR/sbin/"
  fi
done

# Install library
if [ -f "libiw.a" ]; then
  log "Installing libiw.a..."
  cp libiw.a "$INSTALL_DIR/lib/"
fi

# Install headers
if [ -f "iwlib.h" ]; then
  log "Installing iwlib.h..."
  cp iwlib.h "$INSTALL_DIR/include/"
fi

log "Step 5: Fixing TLS alignment for ARM64..."

# Fix TLS alignment for ARM64 binaries
if [ "$TARGET_ARCH" = "arm64" ] || [ "$TARGET_ARCH" = "aarch64" ]; then
  TLS_FIX_SCRIPT="$SCRIPT_DIR/fix-tls-alignment.py"
  if [ -f "$TLS_FIX_SCRIPT" ]; then
    for prog in iwconfig iwlist iwpriv iwspy iwgetid iwevent ifrename; do
      if [ -f "$INSTALL_DIR/sbin/$prog" ]; then
        log "Fixing TLS alignment for $prog..."
        python3 "$TLS_FIX_SCRIPT" "$INSTALL_DIR/sbin/$prog" || log "WARNING: TLS fix failed for $prog"
      fi
    done
  else
    log "WARNING: TLS fix script not found at $TLS_FIX_SCRIPT"
  fi
fi

log "Step 6: Verifying installation..."

if [ ! -d "$INSTALL_DIR/sbin" ] || [ -z "$(ls -A $INSTALL_DIR/sbin)" ]; then
  log "ERROR: No binaries installed"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
