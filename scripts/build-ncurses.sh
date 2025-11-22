#!/bin/bash
# build-ncurses.sh - Build ncurses library for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="ncurses"
TOOL_VERSION="6.5"
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
if [ -d "$SCRIPT_DIR/../src/ncurses" ] && [ ! -d "$SRC_DIR/ncurses-src" ]; then
  log "Using local ncurses source..."
  cp -r "$SCRIPT_DIR/../src/ncurses" "$SRC_DIR/ncurses-src"
elif [ ! -d "$SRC_DIR/ncurses-src" ]; then
  log "Local source not found, downloading $TOOL_NAME $TOOL_VERSION..."
  NCURSES_URL="https://ftp.gnu.org/gnu/ncurses/ncurses-${TOOL_VERSION}.tar.gz"
  NCURSES_ARCHIVE="$BUILD_DIR/ncurses-${TOOL_VERSION}.tar.gz"
  
  if [ ! -f "$NCURSES_ARCHIVE" ]; then
    log_cmd wget -c "$NCURSES_URL" -O "$NCURSES_ARCHIVE"
  else
    log "Source archive already exists: $NCURSES_ARCHIVE"
  fi
  
  log "Extracting $NCURSES_ARCHIVE..."
  cd "$SRC_DIR"
  tar xzf "$NCURSES_ARCHIVE"
  for dir in ncurses*; do
    if [ -d "$dir" ]; then
      mv "$dir" ncurses-src
      break
    fi
  done
else
  log "Using existing source in $SRC_DIR/ncurses-src"
fi

cd "$SRC_DIR/ncurses-src"

log "Step 2: Configuring $TOOL_NAME..."

# Clean previous build
if [ -f Makefile ]; then
  log_cmd make distclean || true
fi

log_cmd ./configure \
  --host="$TARGET_TRIPLE" \
  --prefix="$INSTALL_DIR" \
  --enable-widec \
  --disable-database \
  --with-fallbacks=xterm,xterm-256color,screen,screen-256color,vt100 \
  --without-ada \
  --without-cxx \
  --without-cxx-binding \
  --without-manpages \
  --without-progs \
  --without-tests \
  --enable-static \
  --disable-shared \
  CC="$CC" \
  CFLAGS="$CFLAGS" \
  LDFLAGS="$LDFLAGS"

log "Step 3: Building $TOOL_NAME..."

log_cmd make -j"$PARALLEL_JOBS"

log "Step 4: Installing $TOOL_NAME..."

log_cmd make install

# Create symlinks for non-wide versions
cd "$INSTALL_DIR/lib"
ln -sf libncursesw.a libncurses.a
ln -sf libpanelw.a libpanel.a
ln -sf libmenuw.a libmenu.a
ln -sf libformw.a libform.a

cd "$INSTALL_DIR/include"
ln -sf ncursesw ncurses

log "Step 5: Verifying installation..."
if [ ! -f "$INSTALL_DIR/lib/libncursesw.a" ]; then
  log "ERROR: ncurses library not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
