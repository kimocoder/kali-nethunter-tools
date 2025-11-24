#!/bin/bash
# build-reaver.sh - Build reaver (WPS cracking tool) for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="reaver"
TOOL_VERSION="1.6.6"
TOOL_DEPS=("libpcap" "libnl3")
TOOL_CONFIGURE_OPTS=""
TOOL_PATCHES=("reaver-android.patch")

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

log "Verifying dependencies..."
for dep in "${TOOL_DEPS[@]}"; do
  if [ ! -f "$PREFIX/$dep/.built" ]; then
    log "ERROR: Dependency $dep not built"
    exit 1
  fi
done

log "Step 1: Downloading $TOOL_NAME $TOOL_VERSION..."

REAVER_URL="https://github.com/t6x/reaver-wps-fork-t6x/archive/refs/tags/v1.6.6.tar.gz"
REAVER_ARCHIVE="$BUILD_DIR/reaver-${TOOL_VERSION}.tar.gz"

if [ ! -f "$REAVER_ARCHIVE" ]; then
  log_cmd wget -c "$REAVER_URL" -O "$REAVER_ARCHIVE"
else
  log "Source archive already exists: $REAVER_ARCHIVE"
fi

if [ ! -d "$SRC_DIR/reaver-src" ]; then
  log "Extracting $REAVER_ARCHIVE..."
  cd "$SRC_DIR"
  tar xzf "$REAVER_ARCHIVE"
  for dir in reaver*; do
    if [ -d "$dir" ]; then
      mv "$dir" reaver-src
      break
    fi
  done
fi

cd "$SRC_DIR/reaver-src/src"

log "Step 2: Applying patches..."
# Android doesn't have ualarm, replace it with alarm
# ualarm takes microseconds, alarm takes seconds
if grep -q "ualarm" wpsmon.c 2>/dev/null; then
  log "Replacing ualarm with alarm for Android compatibility"
  # ualarm(CHANNEL_INTERVAL, CHANNEL_INTERVAL) -> alarm(CHANNEL_INTERVAL/1000000)
  # Since CHANNEL_INTERVAL is likely in microseconds, convert to seconds
  # alarm() takes seconds, so we divide by 1000000, with minimum of 1 second
  sed -i 's/ualarm(\([^,]*\),\s*\([^)]*\))/alarm(((\1) \/ 1000000) ? ((\1) \/ 1000000) : 1)/g' wpsmon.c
fi

log "Step 3: Configuring $TOOL_NAME..."

if [ -f Makefile ]; then
  log_cmd make distclean || true
fi

export PKG_CONFIG_PATH="$PREFIX/libpcap/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

log_cmd ./configure \
  --host="$TARGET_TRIPLE" \
  --prefix="$INSTALL_DIR" \
  $TOOL_CONFIGURE_OPTS \
  CC="$CC" CXX="$CXX" \
  CFLAGS="$CFLAGS -I$PREFIX/libpcap/include -I$PREFIX/libnl3/include/libnl3" \
  CXXFLAGS="$CXXFLAGS -I$PREFIX/libpcap/include -I$PREFIX/libnl3/include/libnl3" \
  LDFLAGS="$LDFLAGS -static -L$PREFIX/libpcap/lib -L$PREFIX/libnl3/lib -lnl-genl-3 -lnl-3" \
  LIBS="-lpcap -ldl" \
  ac_cv_lib_pcap_pcap_open_live=yes

log "Step 4: Building $TOOL_NAME..."

# Remove pthread dependency
sed -i 's/-lpthread//' Makefile

# Add libnl3 libraries and paths to Makefile
# libpcap.a depends on libnl3, so we must link against it
sed -i "s|^LIBS.*=.*|& -lnl-genl-3 -lnl-3|" Makefile
sed -i "s|^LIBPATH.*=.*|& -L$PREFIX/libnl3/lib|" Makefile
sed -i "s|^INCPATH.*=.*|& -I$PREFIX/libnl3/include/libnl3|" Makefile

log_cmd make -j"$PARALLEL_JOBS"

log "Step 5: Installing $TOOL_NAME..."
mkdir -p "$INSTALL_DIR/bin"
cp reaver "$INSTALL_DIR/bin/" 2>/dev/null || cp wash "$INSTALL_DIR/bin/" 2>/dev/null || true

# Fix TLS alignment for Android
# Detect architecture from the binary itself, not from TARGET_ARCH
for binary in reaver wash; do
  if [ -f "$INSTALL_DIR/bin/$binary" ]; then
    # Check if binary is 64-bit
    if file "$INSTALL_DIR/bin/$binary" | grep -q "64-bit"; then
      TLS_ALIGN=64
    else
      TLS_ALIGN=32
    fi
    log "Fixing TLS alignment for $binary to $TLS_ALIGN bytes..."
    python3 "$SCRIPT_DIR/fix-tls-alignment.py" "$INSTALL_DIR/bin/$binary" $TLS_ALIGN 2>&1 | tee -a "$LOG_FILE" || log "WARNING: TLS alignment fix failed for $binary"
  fi
done

[ -f "$INSTALL_DIR/bin/reaver" ] && "$STRIP" "$INSTALL_DIR/bin/reaver" 2>/dev/null || true
[ -f "$INSTALL_DIR/bin/wash" ] && "$STRIP" "$INSTALL_DIR/bin/wash" 2>/dev/null || true

log "Step 6: Verifying installation..."
if [ ! -d "$INSTALL_DIR/bin" ]; then
  log "ERROR: bin directory not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
