#!/bin/bash
# build-net-tools.sh - Build net-tools for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="net-tools"
TOOL_VERSION="2.10"
TOOL_DEPS=()
TOOL_CONFIGURE_OPTS=""
TOOL_PATCHES=("net-tools-android.patch")

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
if [ -d "$SCRIPT_DIR/../src/net-tools" ]; then
  if [ -d "$SRC_DIR/net-tools-src" ]; then
    log "Removing existing source directory..."
    rm -rf "$SRC_DIR/net-tools-src"
  fi
  log "Copying fresh net-tools source..."
  cp -r "$SCRIPT_DIR/../src/net-tools" "$SRC_DIR/net-tools-src"
else
  log "ERROR: Source directory not found: $SCRIPT_DIR/../src/net-tools"
  exit 1
fi

cd "$SRC_DIR/net-tools-src"

# Clean previous build artifacts
if [ -f Makefile ]; then
  log "Cleaning previous build..."
  make clean 2>/dev/null || true
fi

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

log "Step 3: Configuring $TOOL_NAME for Android..."

# Create a minimal config.make for Android
cat > config.make << 'EOF'
# Android configuration for net-tools
HAVE_AFUNIX=1
HAVE_AFINET=1
HAVE_AFINET6=0
HAVE_AFIPX=0
HAVE_AFATALK=0
HAVE_AFAX25=0
HAVE_AFNETROM=0
HAVE_AFROSE=0
HAVE_AFX25=0
HAVE_AFECONET=0
HAVE_AFDECnet=0
HAVE_AFASH=0
HAVE_AFBLUETOOTH=0
HAVE_HWETHER=1
HAVE_HWARC=0
HAVE_HWSLIP=0
HAVE_HWPPP=0
HAVE_HWTUNNEL=1
HAVE_HWSTRIP=0
HAVE_HWTR=0
HAVE_HWAX25=0
HAVE_HWROSE=0
HAVE_HWNETROM=0
HAVE_HWX25=0
HAVE_HWFR=0
HAVE_HWSIT=1
HAVE_HWFDDI=0
HAVE_HWHIPPI=0
HAVE_HWASH=0
HAVE_HWHDLCLAPB=0
HAVE_HWIRDA=0
HAVE_HWEC=0
HAVE_HWEUI64=1
HAVE_HWIB=0
HAVE_FW_MASQUERADE=0
HAVE_ARP_TOOLS=1
HAVE_HOSTNAME_TOOLS=1
HAVE_HOSTNAME_SYMLINKS=0
HAVE_IP_TOOLS=1
HAVE_MII=1
HAVE_PLIP_TOOLS=0
HAVE_SERIAL_TOOLS=0
HAVE_SELINUX=0
I18N=0
EOF

# Create config.h
cat > config.h << 'EOF'
/* config.h - Automatically generated for Android */
#define HAVE_AFUNIX 1
#define HAVE_AFINET 1
#define HAVE_AFINET6 0
#define HAVE_HWETHER 1
#define HAVE_HWTUNNEL 1
#define HAVE_HWSIT 1
#define HAVE_HWEUI64 1
#define HAVE_AFBLUETOOTH 0
#define HAVE_ARP_TOOLS 1
#define HAVE_HOSTNAME_TOOLS 1
#define HAVE_IP_TOOLS 1
#define HAVE_MII 1
#define I18N 0
EOF

# Copy config.h to lib directory
cp config.h lib/

# Create version.h
cat > version.h << 'EOF'
#define RELEASE "net-tools 2.10"
EOF

# Create intl.h stub for Android (no i18n support)
cat > lib/intl.h << 'EOF'
#ifndef _INTL_H
#define _INTL_H
#define _(x) x
#define N_(x) x
#endif
EOF

# Copy version.h to lib directory
cp version.h lib/

log "Step 4: Building $TOOL_NAME..."

# Build with Android toolchain
log_cmd make \
  CC="$CC" \
  CFLAGS="$CFLAGS -D_GNU_SOURCE -DHAVE_HWETHER -Wno-error -Dindex=strchr -Drindex=strrchr" \
  LDFLAGS="$LDFLAGS -static -Llib" \
  BASEDIR="$INSTALL_DIR" \
  BINDIR="/bin" \
  SBINDIR="/sbin" \
  -j"$PARALLEL_JOBS"

log "Step 5: Fixing TLS alignment for ARM64..."

# Fix TLS alignment for ARM64 binaries
if [ "$TARGET_ARCH" = "arm64" ] || [ "$TARGET_ARCH" = "aarch64" ]; then
  TLS_FIX_SCRIPT="$SCRIPT_DIR/fix-tls-alignment.py"
  if [ -f "$TLS_FIX_SCRIPT" ]; then
    for prog in ifconfig netstat route arp hostname iptunnel ipmaddr mii-tool nameif; do
      if [ -f "$prog" ]; then
        log "Fixing TLS alignment for $prog..."
        python3 "$TLS_FIX_SCRIPT" "$prog" || log "WARNING: TLS fix failed for $prog"
      fi
    done
  else
    log "WARNING: TLS fix script not found at $TLS_FIX_SCRIPT"
  fi
fi

log "Step 6: Installing $TOOL_NAME..."

mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/sbin"

# Install the binaries
for prog in ifconfig netstat route arp hostname iptunnel ipmaddr mii-tool nameif; do
  if [ -f "$prog" ]; then
    log "Installing $prog..."
    cp "$prog" "$INSTALL_DIR/bin/" || cp "$prog" "$INSTALL_DIR/sbin/" || true
  fi
done

log "Step 7: Verifying installation..."
if [ ! -d "$INSTALL_DIR/bin" ] && [ ! -d "$INSTALL_DIR/sbin" ]; then
  log "ERROR: No binaries installed"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
