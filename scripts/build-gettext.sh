#!/bin/bash
# build-gettext.sh - Build GNU gettext for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="gettext"
TOOL_VERSION="0.22"
TOOL_DEPS=("libiconv")
TOOL_CONFIGURE_OPTS=""
TOOL_PATCHES=()

BUILD_DIR="$SCRIPT_DIR/../build/$TOOL_NAME"
SRC_DIR="$BUILD_DIR/src/gettext-src"
INSTALL_DIR="$PREFIX/$TOOL_NAME"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$(readlink -f "$LOG_DIR")/build-$TOOL_NAME-$(date +%s).log"

mkdir -p "$BUILD_DIR" "$INSTALL_DIR" "$LOG_DIR"

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
if [ -d "$SCRIPT_DIR/../src/gettext" ] && [ ! -d "$SRC_DIR" ]; then
  log "Using local gettext source..."
  mkdir -p "$BUILD_DIR/src"
  cp -r "$SCRIPT_DIR/../src/gettext" "$SRC_DIR"
elif [ ! -d "$SRC_DIR" ]; then
  log "Local source not found, downloading $TOOL_NAME $TOOL_VERSION..."
  GETTEXT_URL="https://ftp.gnu.org/pub/gnu/gettext/gettext-${TOOL_VERSION}.tar.gz"
  GETTEXT_ARCHIVE="$BUILD_DIR/gettext-${TOOL_VERSION}.tar.gz"
  
  if [ ! -f "$GETTEXT_ARCHIVE" ]; then
    log_cmd wget -c "$GETTEXT_URL" -O "$GETTEXT_ARCHIVE"
  else
    log "Source archive already exists: $GETTEXT_ARCHIVE"
  fi
  
  log "Extracting $GETTEXT_ARCHIVE..."
  mkdir -p "$BUILD_DIR/src"
  cd "$BUILD_DIR/src"
  tar xzf "$GETTEXT_ARCHIVE"
  for dir in gettext*; do
    if [ -d "$dir" ]; then
      mv "$dir" gettext-src
      break
    fi
  done
else
  log "Using existing source in $SRC_DIR"
fi

cd "$SRC_DIR"

log "Step 2: Applying patches..."
for patch in "${TOOL_PATCHES[@]}"; do
  if [ -f "$SCRIPT_DIR/../patches/$patch" ]; then
    log "Applying patch: $patch"
    patch -p1 < "$SCRIPT_DIR/../patches/$patch" || log "Patch already applied or failed (continuing)"
  fi
done

log "Step 3: Configuring $TOOL_NAME..."

# Determine simplified host triplet for older autotools
if [[ "$TARGET_TRIPLE" == "armv7a"* ]]; then
  AUTOTOOLS_HOST="arm-linux-androideabi"
elif [[ "$TARGET_TRIPLE" == "aarch64"* ]]; then
  AUTOTOOLS_HOST="aarch64-linux-android"
else
  AUTOTOOLS_HOST="$TARGET_TRIPLE"
fi

log "Using autotools host triplet: $AUTOTOOLS_HOST"

# Clean previous build
if [ -f Makefile ]; then
  log "Cleaning previous build..."
  make distclean 2>/dev/null || true
fi

# Run autogen if needed
if [ ! -f configure ]; then
  if [ -f autogen.sh ]; then
    log "Running autogen.sh..."
    log_cmd ./autogen.sh --skip-gnulib
  elif [ -f configure.ac ]; then
    log "Running autoreconf..."
    log_cmd autoreconf -fiv
  fi
fi

log_cmd ./configure \
  --host="$AUTOTOOLS_HOST" \
  --prefix="$INSTALL_DIR" \
  --enable-static \
  --disable-shared \
  --disable-java \
  --disable-csharp \
  --disable-c++ \
  --disable-libasprintf \
  --disable-openmp \
  --disable-curses \
  --without-emacs \
  --disable-acl \
  --with-included-gettext \
  --with-included-glib \
  --with-included-libcroco \
  --with-included-libunistring \
  --with-included-libxml \
  CC="$CC" \
  CXX="$CXX" \
  CFLAGS="$CFLAGS -I$PREFIX/libiconv/include" \
  CXXFLAGS="$CXXFLAGS -I$PREFIX/libiconv/include" \
  LDFLAGS="$LDFLAGS -L$PREFIX/libiconv/lib" \
  LIBS="-liconv"

log "Step 4: Building $TOOL_NAME..."

log_cmd make -j"$PARALLEL_JOBS"

log "Step 5: Installing $TOOL_NAME..."

log_cmd make install

log "Step 6: Creating pkg-config file..."

mkdir -p "$INSTALL_DIR/lib/pkgconfig"
cat > "$INSTALL_DIR/lib/pkgconfig/gettext.pc" << EOF
prefix=$INSTALL_DIR
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: gettext
Description: Internationalization library
Version: $TOOL_VERSION
Requires: iconv
Libs: -L\${libdir} -lgettextpo -lintl
Cflags: -I\${includedir}
EOF

log "Step 7: Verifying installation..."
if [ ! -f "$INSTALL_DIR/lib/libintl.a" ] && [ ! -f "$INSTALL_DIR/lib/libgettextpo.a" ]; then
  log "WARNING: Neither libintl.a nor libgettextpo.a found, but continuing..."
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
