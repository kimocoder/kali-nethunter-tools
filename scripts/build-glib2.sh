#!/bin/bash
# build-glib2.sh - Build GLib2 for Android
# Note: GLib 2.54+ requires meson build system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="glib2"
TOOL_VERSION="2.78.4"
TOOL_DEPS=("libffi" "pcre2" "zlib" "libintl-lite" "libiconv")

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

# Patch meson.build to manually declare iconv dependency (only if file exists)
if [ -f "meson.build" ]; then
  log "Patching meson.build to manually declare iconv dependency..."
  sed -i "s|libiconv = dependency('iconv')|libiconv = declare_dependency(include_directories: include_directories('$PREFIX/libiconv/include'), link_args: ['-L$PREFIX/libiconv/lib', '-liconv'])|" meson.build
else
  log "WARNING: meson.build not found in $SRC_DIR, skipping patch"
fi

log "Step 1: Configuring $TOOL_NAME with meson..."

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

# Set PKG_CONFIG_PATH for meson (already set above, but ensure it's current)
export PKG_CONFIG_PATH="$PREFIX/libiconv/lib/pkgconfig:$PREFIX/libintl-lite/lib/pkgconfig:$PREFIX/libffi/lib/pkgconfig:$PREFIX/pcre2/lib/pkgconfig:$PREFIX/zlib/lib/pkgconfig"

log_cmd meson setup _build \
  --cross-file=android-cross.txt \
  --prefix="$INSTALL_DIR" \
  --default-library=static \
  --buildtype=release \
  -Dtests=false \
  -Dnls=disabled \
  -Dselinux=disabled \
  -Dlibmount=disabled \
  -Dlibelf=disabled

log "Step 2: Building $TOOL_NAME..."
log_cmd meson compile -C _build -j"$PARALLEL_JOBS"

log "Step 3: Installing $TOOL_NAME..."
log_cmd meson install -C _build

log "Step 4: Verifying installation..."
if [ ! -f "$INSTALL_DIR/lib/libglib-2.0.a" ]; then
  log "ERROR: libglib-2.0.a not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
