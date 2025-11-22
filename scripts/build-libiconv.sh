#!/bin/bash
# build-libiconv.sh - Build GNU libiconv for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="libiconv"
TOOL_VERSION="1.17"
TOOL_DEPS=()
TOOL_CONFIGURE_OPTS=""
TOOL_PATCHES=()

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
if [ -d "$SCRIPT_DIR/../src/libiconv" ] && [ ! -d "$SRC_DIR/libiconv-src" ]; then
  log "Using local libiconv source..."
  cp -r "$SCRIPT_DIR/../src/libiconv" "$SRC_DIR/libiconv-src"
elif [ ! -d "$SRC_DIR/libiconv-src" ]; then
  log "Local source not found, downloading $TOOL_NAME $TOOL_VERSION..."
  LIBICONV_URL="https://ftp.gnu.org/pub/gnu/libiconv/libiconv-${TOOL_VERSION}.tar.gz"
  LIBICONV_ARCHIVE="$BUILD_DIR/libiconv-${TOOL_VERSION}.tar.gz"
  
  if [ ! -f "$LIBICONV_ARCHIVE" ]; then
    log_cmd wget -c "$LIBICONV_URL" -O "$LIBICONV_ARCHIVE"
  else
    log "Source archive already exists: $LIBICONV_ARCHIVE"
  fi
  
  log "Extracting $LIBICONV_ARCHIVE..."
  cd "$SRC_DIR"
  tar xzf "$LIBICONV_ARCHIVE"
  for dir in libiconv*; do
    if [ -d "$dir" ]; then
      mv "$dir" libiconv-src
      break
    fi
  done
else
  log "Using existing source in $SRC_DIR/libiconv-src"
fi

cd "$SRC_DIR/libiconv-src"

log "Step 2: Applying patches..."
for patch in "${TOOL_PATCHES[@]}"; do
  if [ -f "$SCRIPT_DIR/patches/$patch" ]; then
    log "Applying patch: $patch"
    patch -p1 < "$SCRIPT_DIR/patches/$patch" || log "Patch already applied or failed (continuing)"
  fi
done

log "Step 3: Configuring $TOOL_NAME..."

# Clean previous build
if [ -f Makefile ]; then
  log_cmd make distclean || true
fi

log_cmd ./configure \
  --host="$TARGET_TRIPLE" \
  --prefix="$INSTALL_DIR" \
  --enable-static \
  --disable-shared \
  CC="$CC" \
  CFLAGS="$CFLAGS" \
  LDFLAGS="$LDFLAGS"

log "Step 4: Building $TOOL_NAME..."

log_cmd make -j"$PARALLEL_JOBS"

log "Step 5: Installing $TOOL_NAME..."

log_cmd make install

log "Step 6: Creating pkg-config file..."

mkdir -p "$INSTALL_DIR/lib/pkgconfig"
cat > "$INSTALL_DIR/lib/pkgconfig/iconv.pc" << EOF
prefix=$INSTALL_DIR
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: iconv
Description: Character set conversion library
Version: $TOOL_VERSION
Libs: -L\${libdir} -liconv
Cflags: -I\${includedir}
EOF

log "Step 7: Verifying installation..."
if [ ! -f "$INSTALL_DIR/lib/libiconv.a" ]; then
  log "ERROR: libiconv.a not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
