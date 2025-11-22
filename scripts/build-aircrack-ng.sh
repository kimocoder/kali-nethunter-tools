#!/bin/bash
# build-aircrack-ng.sh - Build aircrack-ng for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="aircrack-ng"
TOOL_VERSION="1.7"
TOOL_DEPS=("libnet" "libpcap" "openssl" "libnl3")
TOOL_CONFIGURE_OPTS=""
TOOL_PATCHES=("aircrack-ng-android.patch")

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

log "Step 1: Preparing $TOOL_NAME source..."

# Check for local source first
if [ -d "$SCRIPT_DIR/../src/aircrack-ng" ] && [ ! -d "$SRC_DIR/aircrack-ng-src" ]; then
  log "Using local aircrack-ng source..."
  cp -r "$SCRIPT_DIR/../src/aircrack-ng" "$SRC_DIR/aircrack-ng-src"
elif [ ! -d "$SRC_DIR/aircrack-ng-src" ]; then
  log "Local source not found, downloading $TOOL_NAME $TOOL_VERSION..."
  AIRCRACK_URL="https://github.com/aircrack-ng/aircrack-ng/archive/refs/tags/1.7.tar.gz"
  AIRCRACK_ARCHIVE="$BUILD_DIR/aircrack-ng-${TOOL_VERSION}.tar.gz"
  
  if [ ! -f "$AIRCRACK_ARCHIVE" ]; then
    log_cmd wget -c "$AIRCRACK_URL" -O "$AIRCRACK_ARCHIVE"
  else
    log "Source archive already exists: $AIRCRACK_ARCHIVE"
  fi
  
  log "Extracting $AIRCRACK_ARCHIVE..."
  cd "$SRC_DIR"
  tar xzf "$AIRCRACK_ARCHIVE"
  for dir in aircrack*; do
    if [ -d "$dir" ]; then
      mv "$dir" aircrack-ng-src
      break
    fi
  done
else
  log "Using existing source in $SRC_DIR/aircrack-ng-src"
fi

cd "$SRC_DIR/aircrack-ng-src"

log "Step 2: Patching for Android..."

# Patch console.c to stub out nl_langinfo which doesn't exist on Android
if [ -f "lib/libac/tui/console.c" ]; then
  log "Patching console.c for Android nl_langinfo compatibility"
  sed -i '/#include <langinfo.h>/a\
#ifdef __ANDROID__\
#ifndef CODESET\
#define CODESET 0\
#endif\
#define nl_langinfo(x) "UTF-8"\
#endif' lib/libac/tui/console.c
fi

log "Step 3: Configuring $TOOL_NAME..."

if [ -f Makefile ]; then
  log_cmd make distclean || true
fi

if [ ! -f configure ]; then
  log "Generating configure script..."
  log_cmd autoreconf -fi || true
fi

export PKG_CONFIG_PATH="$PREFIX/openssl/lib/pkgconfig:$PREFIX/libpcap/lib/pkgconfig:$PREFIX/libnet/lib/pkgconfig:$PREFIX/libnl3/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export PKG_CONFIG_LIBDIR="$PREFIX/openssl/lib/pkgconfig:$PREFIX/libpcap/lib/pkgconfig:$PREFIX/libnet/lib/pkgconfig:$PREFIX/libnl3/lib/pkgconfig"

log_cmd ./configure \
  --host="$TARGET_TRIPLE" \
  --prefix="$INSTALL_DIR" \
  $TOOL_CONFIGURE_OPTS \
  --with-libpcap="$PREFIX/libpcap" \
  --with-libnet="$PREFIX/libnet" \
  --with-openssl="$PREFIX/openssl" \
  --enable-libnl \
  --enable-static \
  --disable-shared \
  CC="$CC" CXX="$CXX" \
  CPPFLAGS="-I$PREFIX/libpcap/include -I$PREFIX/libnet/include -I$PREFIX/openssl/include -I$PREFIX/libnl3/include/libnl3 -Dfseeko=fseek -Dftello=ftell" \
  CFLAGS="$CFLAGS" \
  CXXFLAGS="$CXXFLAGS -Dfseeko=fseek -Dftello=ftell" \
  LDFLAGS="$LDFLAGS -static -L$PREFIX/libpcap/lib -L$PREFIX/libnet/lib -L$PREFIX/openssl/lib -L$PREFIX/libnl3/lib -L$PREFIX/zlib/lib" \
  LIBS="-ldl -lz"

log "Step 4: Building $TOOL_NAME..."
log_cmd make -j"$PARALLEL_JOBS"

log "Step 5: Installing $TOOL_NAME..."
log_cmd make install

log "Step 6: Verifying installation..."
if [ ! -d "$INSTALL_DIR/bin" ]; then
  log "ERROR: bin directory not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
