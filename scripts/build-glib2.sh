#!/bin/bash
# build-glib2.sh - Build GLib2 for Android
# Note: GLib 2.54+ requires meson build system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="glib2"
TOOL_VERSION="2.78.4"
TOOL_DEPS=("libffi" "pcre2" "zlib" "libintl-lite" "libiconv" "gettext")

BUILD_DIR="$SCRIPT_DIR/../build/$TOOL_NAME"
SRC_DIR="$BUILD_DIR/src/glib-src"
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

# Check for meson and ninja
if ! command -v meson &> /dev/null; then
  log "ERROR: meson not found. Install with: pip3 install meson"
  exit 1
fi

if ! command -v ninja &> /dev/null; then
  log "ERROR: ninja not found. Install with: pip3 install ninja or apt install ninja-build"
  exit 1
fi

# Use local source or download if not present
if [ ! -d "$SRC_DIR" ]; then
  mkdir -p "$BUILD_DIR/src"
  # Check for local source first
  if [ -d "$SCRIPT_DIR/../src/glib" ]; then
    log "Using local glib source..."
    cp -r "$SCRIPT_DIR/../src/glib" "$SRC_DIR"
  elif [ -d "$SCRIPT_DIR/../src/glib2" ]; then
    log "Using local glib2 source..."
    cp -r "$SCRIPT_DIR/../src/glib2" "$SRC_DIR"
  else
    log "Local source not found, downloading glib $TOOL_VERSION..."
    cd "$BUILD_DIR"
    GLIB_URL="https://download.gnome.org/sources/glib/2.78/glib-$TOOL_VERSION.tar.xz"
    log_cmd wget -O glib-$TOOL_VERSION.tar.xz "$GLIB_URL"
    log_cmd tar xf glib-$TOOL_VERSION.tar.xz
    mv "glib-$TOOL_VERSION" "$SRC_DIR"
  fi
fi

# Ensure we're in the source directory before patching
if [ ! -d "$SRC_DIR" ]; then
  log "ERROR: Source directory $SRC_DIR does not exist"
  exit 1
fi

cd "$SRC_DIR"

# Initialize meson subprojects if using meson
if [ -f "meson.build" ] && [ -d "subprojects" ]; then
  log "Initializing meson subprojects..."
  # Download gvdb subproject if missing
  if [ -f "subprojects/gvdb.wrap" ] && [ ! -f "subprojects/gvdb/meson.build" ]; then
    log "Cloning gvdb subproject..."
    rm -rf subprojects/gvdb
    git clone --depth=1 https://gitlab.gnome.org/GNOME/gvdb.git subprojects/gvdb 2>&1 | tee -a "$LOG_FILE" || {
      log "ERROR: Failed to clone gvdb subproject"
      exit 1
    }
  fi
fi

# Detect build system (autotools vs meson)
if [ -f "meson.build" ]; then
  BUILD_SYSTEM="meson"
  log "Detected meson build system"
  
  # Patch meson.build to manually declare iconv dependency
  log "Patching meson.build to manually declare iconv dependency..."
  sed -i "s|libiconv = dependency('iconv')|libiconv = declare_dependency(include_directories: include_directories('$PREFIX/libiconv/include'), link_args: ['-L$PREFIX/libiconv/lib', '-liconv'])|" meson.build
elif [ -f "configure.in" ] || [ -f "configure.ac" ]; then
  BUILD_SYSTEM="autotools"
  log "Detected autotools build system (old glib 2.9.6)"
else
  log "ERROR: Could not detect build system"
  exit 1
fi

if [ "$BUILD_SYSTEM" = "meson" ]; then
  log "Step 1: Configuring $TOOL_NAME with meson..."
elif [ "$BUILD_SYSTEM" = "autotools" ]; then
  log "Step 1: Configuring $TOOL_NAME with autotools..."
fi

if [ "$BUILD_SYSTEM" = "meson" ]; then
  # ============================================================================
  # Meson Build Path (for glib 2.54+)
  # ============================================================================
  
  export PKG_CONFIG_PATH="$PREFIX/libiconv/lib/pkgconfig:$PREFIX/libffi/lib/pkgconfig:$PREFIX/pcre2/lib/pkgconfig:$PREFIX/zlib/lib/pkgconfig:$PREFIX/libintl-lite/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

  # Determine CPU family based on TARGET_TRIPLE
  if [[ "$TARGET_TRIPLE" == "aarch64"* ]]; then
    CPU_FAMILY="aarch64"
    CPU="armv8"
  elif [[ "$TARGET_TRIPLE" == "armv7a"* ]]; then
    CPU_FAMILY="arm"
    CPU="armv7a"
  else
    CPU_FAMILY="aarch64"
    CPU="armv8"
  fi

  # Create a wrapper script for pkg-config that sets the path
  cat > pkg-config-wrapper.sh << 'PKGWRAP'
#!/bin/bash
export PKG_CONFIG_PATH="$PKG_CONFIG_PATH"
exec pkg-config "$@"
PKGWRAP
  chmod +x pkg-config-wrapper.sh

  # Create cross-compilation file for meson
  cat > android-cross.txt << EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
strip = '$STRIP'
pkg-config = '$(pwd)/pkg-config-wrapper.sh'

[built-in options]
c_args = ['-I$PREFIX/libiconv/include', '-I$PREFIX/pcre2/include', '-I$PREFIX/libffi/include', '-I$PREFIX/zlib/include', '-I$PREFIX/libintl-lite/include']
c_link_args = ['-L$PREFIX/libiconv/lib', '-L$PREFIX/pcre2/lib', '-L$PREFIX/libffi/lib', '-L$PREFIX/zlib/lib', '-L$PREFIX/libintl-lite/lib', '-liconv', '-lintl']

[properties]
sys_root = '$SYSROOT'

[host_machine]
system = 'android'
cpu_family = '$CPU_FAMILY'
cpu = '$CPU'
endian = 'little'
EOF

  # Clean previous build
  rm -rf _build

  log_cmd meson setup _build \
    --cross-file=android-cross.txt \
    --prefix="$INSTALL_DIR" \
    --default-library=static \
    --buildtype=release \
    --wrap-mode=forcefallback \
    -Dtests=false \
    -Dnls=disabled \
    -Dselinux=disabled \
    -Dlibmount=disabled \
    -Dlibelf=disabled

  log "Step 2: Building $TOOL_NAME..."
  log_cmd meson compile -C _build -j"$PARALLEL_JOBS"

  log "Step 3: Installing $TOOL_NAME..."
  log_cmd meson install -C _build

elif [ "$BUILD_SYSTEM" = "autotools" ]; then
  # ============================================================================
  # Autotools Build Path (for glib 2.9.6)
  # ============================================================================
  
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
  
  # Run configure if it doesn't exist
  if [ ! -f configure ]; then
    log "Running autogen.sh..."
    log_cmd ./autogen.sh
  fi
  
  # Set up environment for gettext detection
  export INTLLIBS="-L$PREFIX/gettext/lib -lintl -L$PREFIX/libiconv/lib -liconv"
  export INTL_MACOSX_LIBS=""
  
  # Create a config.cache file with cross-compilation answers
  cat > config.cache << EOF
# Cross-compilation cache for glib 2.9.6
ac_cv_c_bigendian=no
glib_cv_stack_grows=no
glib_cv_uscore=no
glib_cv_has__inline=yes
glib_cv_has__inline__=yes
glib_cv_hasinline=yes
glib_cv_sane_realloc=yes
glib_cv_va_copy=no
glib_cv___va_copy=yes
glib_cv_va_val_copy=yes
glib_cv_rtldglobal_broken=no
glib_cv_sys_pthread_mutex_trylock_posix=yes
glib_cv_sys_pthread_getspecific_posix=yes
glib_cv_sys_pthread_cond_timedwait_posix=yes
ac_cv_func_posix_getpwuid_r=yes
ac_cv_func_posix_getgrgid_r=yes
glib_cv_sizeof_gmutex=24
glib_cv_sizeof_system_thread=4
EOF
  
  log_cmd ./configure \
    --build=x86_64-linux-gnu \
    --host="$AUTOTOOLS_HOST" \
    --prefix="$INSTALL_DIR" \
    --enable-static \
    --disable-shared \
    --disable-gtk-doc \
    --disable-man \
    --with-libiconv=gnu \
    --with-libintl-prefix="$PREFIX/gettext" \
    --cache-file=config.cache \
    CC="$CC" \
    CXX="$CXX" \
    CPPFLAGS="-I$PREFIX/gettext/include -I$PREFIX/libiconv/include -I$PREFIX/libintl-lite/include" \
    CFLAGS="$CFLAGS -I$PREFIX/libiconv/include -I$PREFIX/libintl-lite/include -I$PREFIX/gettext/include" \
    CXXFLAGS="$CXXFLAGS -I$PREFIX/libiconv/include -I$PREFIX/libintl-lite/include -I$PREFIX/gettext/include" \
    LDFLAGS="$LDFLAGS -L$PREFIX/gettext/lib -L$PREFIX/libiconv/lib -L$PREFIX/libintl-lite/lib -static -Wl,--allow-multiple-definition" \
    LIBS="-lintl -liconv"

  log "Step 2: Building $TOOL_NAME..."
  log_cmd make -j"$PARALLEL_JOBS"

  log "Step 3: Installing $TOOL_NAME..."
  log_cmd make install

fi

log "Step 4: Verifying installation..."
if [ ! -f "$INSTALL_DIR/lib/libglib-2.0.a" ]; then
  log "ERROR: libglib-2.0.a not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
