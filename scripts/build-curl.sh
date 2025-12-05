#!/bin/bash
# build-curl.sh - Build curl for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="curl"
TOOL_VERSION="8.0.0"
TOOL_DEPS=(openssl zlib)
TOOL_CONFIGURE_OPTS="--disable-shared"
TOOL_PATCHES=("curl-android.patch")

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
if [ -d "$SCRIPT_DIR/../src/curl" ] && [ ! -d "$SRC_DIR/curl-src" ]; then
  log "Using local curl source..."
  cp -r "$SCRIPT_DIR/../src/curl" "$SRC_DIR/curl-src"
elif [ ! -d "$SRC_DIR/curl-src" ]; then
  log "Local source not found, downloading $TOOL_NAME $TOOL_VERSION..."
  CURL_URL="https://github.com/curl/curl/archive/refs/tags/curl-8_0_0.tar.gz"
  CURL_ARCHIVE="$BUILD_DIR/curl-${TOOL_VERSION}.tar.gz"
  
  if [ ! -f "$CURL_ARCHIVE" ]; then
    log_cmd wget -c "$CURL_URL" -O "$CURL_ARCHIVE"
  else
    log "Source archive already exists: $CURL_ARCHIVE"
  fi
  
  log "Extracting $CURL_ARCHIVE..."
  cd "$SRC_DIR"
  tar xzf "$CURL_ARCHIVE"
  for dir in curl*; do
    if [ -d "$dir" ]; then
      mv "$dir" curl-src
      break
    fi
  done
else
  log "Using existing source in $SRC_DIR/curl-src"
fi

cd "$SRC_DIR/curl-src"

log "Step 2: Applying patches..."
for patch in "${TOOL_PATCHES[@]}"; do
  if [ -f "$SCRIPT_DIR/patches/$patch" ]; then
    log "Applying patch: $patch"
    patch -p1 < "$SCRIPT_DIR/patches/$patch" || log "Patch already applied or failed (continuing)"
  fi
done

log "Step 3: Configuring $TOOL_NAME..."

if [ -f Makefile ]; then
  log_cmd make distclean || true
fi

if [ ! -f configure ]; then
  log "Generating configure script..."
  if [ -f buildconf ]; then
    log_cmd ./buildconf
  else
    log_cmd autoreconf -fi
  fi
fi

log_cmd ./configure \
  --host="$TARGET_TRIPLE" \
  --prefix="$INSTALL_DIR" \
  $TOOL_CONFIGURE_OPTS \
  --with-openssl="$PREFIX/openssl" \
  --with-ca-bundle=/system/etc/security/cacerts \
  --with-zlib="$PREFIX/zlib" \
  CPPFLAGS="-I$PREFIX/openssl/include -I$PREFIX/zlib/include" \
  LDFLAGS="-L$PREFIX/openssl/lib -L$PREFIX/zlib/lib" \
  --without-libpsl \
  --disable-ldap \
  --disable-ldaps \
  --enable-static \
  --disable-shared \
  --disable-manual \
  CC="$CC" CXX="$CXX" \
  CFLAGS="$CFLAGS -I$PREFIX/zlib/include" \
  CXXFLAGS="$CXXFLAGS -I$PREFIX/zlib/include" \
  LDFLAGS="$LDFLAGS -static -L$PREFIX/zlib/lib" \
  LIBS="-lz"

log "Step 4: Building $TOOL_NAME..."
log_cmd make -j"$PARALLEL_JOBS"

log "Step 5: Installing $TOOL_NAME..."
log_cmd make install

log "Step 6: Verifying installation..."
if [ ! -f "$INSTALL_DIR/bin/curl" ]; then
  log "ERROR: curl executable not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
