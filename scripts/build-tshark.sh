#!/bin/bash
# build-tshark.sh - Build tshark (Wireshark CLI) for Android
# This script downloads, configures, and builds tshark for cross-compilation to Android
# Depends on: libpcap

set -euo pipefail

# Source environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

# ============================================================================
# Tool Configuration
# ============================================================================
TOOL_NAME="tshark"
TOOL_VERSION="4.0.0"
TOOL_DEPS=("libpcap" "glib2" "zlib" "c-ares" "libgcrypt" "pcre2" "libxml2" "libintl-lite" "libnl3")  # Dependencies
TOOL_CONFIGURE_OPTS="--disable-shared"
TOOL_PATCHES=("wireshark-android-bonding.patch" "wireshark-android-index-fix.patch")

# ============================================================================
# Verify Dependencies
# ============================================================================
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Verifying dependencies for $TOOL_NAME..."

for dep in "${TOOL_DEPS[@]}"; do
  DEP_DIR="$PREFIX/$dep"
  if [ ! -f "$DEP_DIR/.built" ]; then
    log "ERROR: Dependency $dep not built. Please build it first."
    exit 1
  fi
  log "Dependency $dep found at $DEP_DIR"
done

# ============================================================================
# Directories
# ============================================================================
BUILD_DIR="$SCRIPT_DIR/build/$TOOL_NAME"
SRC_DIR="$BUILD_DIR/src"
INSTALL_DIR="$PREFIX/$TOOL_NAME"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$(readlink -f "$LOG_DIR")/build-$TOOL_NAME-$(date +%s).log"

mkdir -p "$BUILD_DIR" "$SRC_DIR" "$INSTALL_DIR" "$LOG_DIR"

# ============================================================================
# Logging
# ============================================================================
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

# ============================================================================
# Use Local Source
# ============================================================================
log "Step 1: Using local wireshark source..."

WIRESHARK_SRC="$SCRIPT_DIR/../src/wireshark"

if [ ! -d "$WIRESHARK_SRC" ]; then
  log "ERROR: Wireshark source not found at $WIRESHARK_SRC"
  exit 1
fi

cd "$WIRESHARK_SRC"

# ============================================================================
# Apply Patches
# ============================================================================
log "Step 2: Applying patches..."

for patch in "${TOOL_PATCHES[@]}"; do
  if [ -f "$SCRIPT_DIR/patches/$patch" ]; then
    log "Applying patch: $patch"
    patch -p1 < "$SCRIPT_DIR/patches/$patch" || log "Patch already applied or failed (continuing)"
  fi
done

# ============================================================================
# Configure
# ============================================================================
log "Step 3: Configuring $TOOL_NAME..."

# Wireshark uses CMake, not autotools
# Clean and recreate build directory to avoid permission issues
rm -rf build
mkdir -p build
cd build

# Set up pkg-config path for dependencies
export PKG_CONFIG_PATH="$PREFIX/libpcap/lib/pkgconfig:$PREFIX/glib2/lib/pkgconfig:$PREFIX/zlib/lib/pkgconfig:$PREFIX/c-ares/lib/pkgconfig:$PREFIX/libgcrypt/lib/pkgconfig:$PREFIX/libgpg-error/lib/pkgconfig:$PREFIX/libxml2/lib/pkgconfig:$PREFIX/libnl3/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

# Build lemon for host system first
log "Building lemon parser generator for host..."
gcc "$WIRESHARK_SRC/tools/lemon/lemon.c" -o /tmp/lemon

# Create CMake initial cache to skip problematic tests
cat > InitialCache.cmake << 'EOF'
set(HAVE_INFLATE 1 CACHE BOOL "Have inflate function")
set(HAVE_INFLATEPRIME 1 CACHE BOOL "Have inflatePrime function")
EOF

# Determine CMake Android ABI based on target triple
if [[ "$TARGET_TRIPLE" == aarch64* ]]; then
  CMAKE_ANDROID_ABI="arm64-v8a"
elif [[ "$TARGET_TRIPLE" == armv7a* ]]; then
  CMAKE_ANDROID_ABI="armeabi-v7a"
else
  log "ERROR: Unsupported target triple: $TARGET_TRIPLE"
  exit 1
fi

# Configure with CMake for Android
log_cmd cmake .. \
  -C InitialCache.cmake \
  -DCMAKE_SYSTEM_NAME=Android \
  -DCMAKE_SYSTEM_VERSION="$API_LEVEL" \
  -DCMAKE_ANDROID_ARCH_ABI="$CMAKE_ANDROID_ABI" \
  -DCMAKE_ANDROID_NDK="$ANDROID_NDK" \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DLEMON_EXECUTABLE=/tmp/lemon \
  -DCMAKE_C_FLAGS="${CFLAGS/-D_GNU_SOURCE/} -I$PREFIX/libpcap/include -I$PREFIX/glib2/include/glib-2.0 -I$PREFIX/glib2/lib/glib-2.0/include -I$PREFIX/zlib/include -I$PREFIX/c-ares/include -I$PREFIX/libgcrypt/include -I$PREFIX/libgpg-error/include -I$PREFIX/libxml2/include/libxml2 -I$PREFIX/libnl3/include/libnl3 -I$PREFIX/ifaddrs/include -Wno-documentation -Wno-shorten-64-to-32 -Wno-incompatible-pointer-types -Wno-int-to-void-pointer-cast -Wno-void-pointer-to-int-cast -Wno-incompatible-function-pointer-types -Wno-constant-conversion -Wno-implicit-function-declaration" \
  -DCMAKE_CXX_FLAGS="${CXXFLAGS/-D_GNU_SOURCE/} -I$PREFIX/libpcap/include -I$PREFIX/glib2/include/glib-2.0 -I$PREFIX/glib2/lib/glib-2.0/include -I$PREFIX/zlib/include -I$PREFIX/c-ares/include -I$PREFIX/libgcrypt/include -I$PREFIX/libgpg-error/include -I$PREFIX/libxml2/include/libxml2 -I$PREFIX/libnl3/include/libnl3 -I$PREFIX/ifaddrs/include -Wno-documentation -Wno-shorten-64-to-32 -Wno-incompatible-pointer-types -Wno-int-to-void-pointer-cast -Wno-void-pointer-to-int-cast -Wno-incompatible-function-pointer-types -Wno-constant-conversion -Wno-implicit-function-declaration" \
  -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS -static -L$PREFIX/libpcap/lib -L$PREFIX/glib2/lib -L$PREFIX/zlib/lib -L$PREFIX/c-ares/lib -L$PREFIX/libgcrypt/lib -L$PREFIX/libgpg-error/lib -L$PREFIX/libxml2/lib -L$PREFIX/libintl-lite/lib -L$PREFIX/pcre2/lib -L$PREFIX/libffi/lib -L$PREFIX/libnl3/lib -L$PREFIX/ifaddrs/lib -L$PREFIX/libiconv/lib $PREFIX/libintl-lite/lib/libintl.a $PREFIX/glib2/lib/libglib-2.0.a $PREFIX/glib2/lib/libgobject-2.0.a $PREFIX/pcre2/lib/libpcre2-8.a $PREFIX/libffi/lib/libffi.a $PREFIX/zlib/lib/libz.a $PREFIX/libnl3/lib/libnl-3.a $PREFIX/libnl3/lib/libnl-genl-3.a $PREFIX/libnl3/lib/libnl-route-3.a $PREFIX/ifaddrs/lib/libifaddrs.a $PREFIX/libiconv/lib/libiconv.a -lc++ -lm" \
  -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DCMAKE_FIND_ROOT_PATH="$PREFIX" \
  -DCMAKE_PREFIX_PATH="$PREFIX/libgcrypt;$PREFIX/libgpg-error;$PREFIX/glib2;$PREFIX/zlib;$PREFIX/c-ares;$PREFIX/libpcap;$PREFIX/pcre2;$PREFIX/libxml2" \
  -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DGCRYPT_INCLUDE_DIR="$PREFIX/libgcrypt/include" \
  -DGCRYPT_LIBRARY="$PREFIX/libgcrypt/lib/libgcrypt.a" \
  -DGCRYPT_ERROR_LIBRARY="$PREFIX/libgpg-error/lib/libgpg-error.a" \
  -DPCRE2_INCLUDE_DIR="$PREFIX/pcre2/include" \
  -DPCRE2_LIBRARY="$PREFIX/pcre2/lib/libpcre2-8.a" \
  -DLIBXML2_INCLUDE_DIR="$PREFIX/libxml2/include/libxml2" \
  -DLIBXML2_LIBRARY="$PREFIX/libxml2/lib/libxml2.a" \
  -DZLIB_INCLUDE_DIR="$PREFIX/zlib/include" \
  -DZLIB_LIBRARY="$PREFIX/zlib/lib/libz.a" \
  -DHAVE_INFLATE=1 \
  -DHAVE_INFLATEPRIME=1 \
  -DHAVE_PCAP_SET_TSTAMP_PRECISION=1 \
  -DBUILD_wireshark=OFF \
  -DBUILD_stratoshark=OFF \
  -DBUILD_sharkd=OFF \
  -DBUILD_qtui=OFF \
  -DBUILD_tshark=ON \
  -DENABLE_STATIC=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DENABLE_PLUGINS=OFF \
  -DENABLE_LUA=OFF \
  -DENABLE_PYTHON=OFF \
  -DENABLE_PCAP=ON \
  -DENABLE_NL=ON \
  -DENABLE_NETLINK=ON \
  -DNL_INCLUDE_DIR="$PREFIX/libnl3/include/libnl3" \
  -DNL_LIBRARY="$PREFIX/libnl3/lib/libnl-3.a" \
  -DNL_GENL_LIBRARY="$PREFIX/libnl3/lib/libnl-genl-3.a" \
  -DNL_ROUTE_LIBRARY="$PREFIX/libnl3/lib/libnl-route-3.a" \
  -DENABLE_GNUTLS=OFF \
  -DENABLE_LZ4=OFF \
  -DENABLE_ZSTD=OFF \
  -DENABLE_NGHTTP2=OFF

# ============================================================================
# Build
# ============================================================================
log "Step 4: Building $TOOL_NAME..."

log_cmd make -j"$PARALLEL_JOBS"

# ============================================================================
# Install
# ============================================================================
log "Step 5: Installing $TOOL_NAME..."

log_cmd make install

# ============================================================================
# Verify Installation
# ============================================================================
log "Step 6: Verifying installation..."

if [ ! -d "$INSTALL_DIR/bin" ]; then
  log "ERROR: bin directory not found in $INSTALL_DIR"
  exit 1
fi

if [ ! -f "$INSTALL_DIR/bin/tshark" ]; then
  log "ERROR: tshark executable not found in $INSTALL_DIR/bin"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"

# Create marker file
touch "$INSTALL_DIR/.built"

log "Build log saved to: $LOG_FILE"
