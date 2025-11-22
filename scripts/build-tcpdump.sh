#!/bin/bash
# build-tcpdump.sh - Build tcpdump for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="tcpdump"
TOOL_VERSION="4.99.1"
TOOL_DEPS=("libpcap" "libnl3")
TOOL_CONFIGURE_OPTS="--disable-shared"
TOOL_PATCHES=("tcpdump-android.patch")

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
if [ -d "$SCRIPT_DIR/../src/tcpdump" ] && [ ! -d "$SRC_DIR/tcpdump-src" ]; then
  log "Using local tcpdump source..."
  cp -r "$SCRIPT_DIR/../src/tcpdump" "$SRC_DIR/tcpdump-src"
elif [ ! -d "$SRC_DIR/tcpdump-src" ]; then
  log "Local source not found, downloading $TOOL_NAME $TOOL_VERSION..."
  TCPDUMP_URL="https://github.com/the-tcpdump-group/tcpdump/archive/refs/tags/tcpdump-4.99.1.tar.gz"
  TCPDUMP_ARCHIVE="$BUILD_DIR/tcpdump-${TOOL_VERSION}.tar.gz"
  
  if [ ! -f "$TCPDUMP_ARCHIVE" ]; then
    log_cmd wget -c "$TCPDUMP_URL" -O "$TCPDUMP_ARCHIVE"
  else
    log "Source archive already exists: $TCPDUMP_ARCHIVE"
  fi
  
  log "Extracting $TCPDUMP_ARCHIVE..."
  cd "$SRC_DIR"
  tar xzf "$TCPDUMP_ARCHIVE"
  for dir in tcpdump*; do
    if [ -d "$dir" ]; then
      mv "$dir" tcpdump-src
      break
    fi
  done
else
  log "Using existing source in $SRC_DIR/tcpdump-src"
fi

cd "$SRC_DIR/tcpdump-src"

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
  log_cmd autoreconf -fi || true
fi

export PKG_CONFIG_PATH="$PREFIX/libpcap/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

log_cmd ./configure \
  --host="$TARGET_TRIPLE" \
  --prefix="$INSTALL_DIR" \
  $TOOL_CONFIGURE_OPTS \
  --with-pcap=linux \
  CC="$CC" CXX="$CXX" \
  CFLAGS="$CFLAGS -I$PREFIX/libpcap/include -I$PREFIX/libnl3/include/libnl3" \
  CXXFLAGS="$CXXFLAGS -I$PREFIX/libpcap/include -I$PREFIX/libnl3/include/libnl3" \
  LDFLAGS="$LDFLAGS -static -L$PREFIX/libpcap/lib -L$PREFIX/libnl3/lib" \
  LIBS="-lpcap -lnl-3 -lnl-genl-3 -ldl" \
  ac_cv_linux_vers=4 \
  ac_cv_func_pcap_loop=yes \
  ac_cv_func_pcap_create=yes

log "Step 4: Building $TOOL_NAME..."
log_cmd make -j"$PARALLEL_JOBS"

log "Step 5: Installing $TOOL_NAME..."
log_cmd make install

log "Step 6: Verifying installation..."
if [ ! -f "$INSTALL_DIR/bin/tcpdump" ]; then
  log "ERROR: tcpdump executable not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
