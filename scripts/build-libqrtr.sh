#!/bin/bash
# build-libqrtr.sh - Build libqrtr (Qualcomm IPC Router library) for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="libqrtr"
TOOL_VERSION="1.0"
TOOL_DEPS=()
TOOL_PATCHES=("libqrtr-static.patch")

BUILD_DIR="$SCRIPT_DIR/../build/$TOOL_NAME"
SRC_DIR="$SCRIPT_DIR/../src/$TOOL_NAME"
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

if [ ! -d "$SRC_DIR" ]; then
  log "ERROR: Source directory not found: $SRC_DIR"
  exit 1
fi

# Check for meson and ninja
if ! command -v meson &> /dev/null; then
  log "ERROR: meson not found. Install with: pip3 install meson"
  exit 1
fi

if ! command -v ninja &> /dev/null; then
  log "ERROR: ninja not found. Install with: pip3 install ninja or apt install ninja-build"
  exit 1
fi

log "Step 1: Preparing build directory..."

# Create meson build directory (clean it if it exists to avoid cross-contamination)
MESON_BUILD_DIR="$BUILD_DIR/build"
if [ -d "$MESON_BUILD_DIR" ]; then
  log "Removing existing build directory to ensure clean build..."
  rm -rf "$MESON_BUILD_DIR"
fi
mkdir -p "$MESON_BUILD_DIR"

log "Step 2: Applying patches..."
cd "$SRC_DIR"
for patch in "${TOOL_PATCHES[@]}"; do
  if [ -f "$SCRIPT_DIR/../patches/$patch" ]; then
    log "Applying patch: $patch"
    patch -p1 < "$SCRIPT_DIR/../patches/$patch" || log "Patch already applied or failed (continuing)"
  fi
done

log "Step 3: Configuring $TOOL_NAME with meson..."

# Create cross-compilation file for meson
CROSS_FILE="$BUILD_DIR/android-cross.txt"

# Parse CFLAGS and LDFLAGS into arrays for meson
IFS=' ' read -ra CFLAGS_ARRAY <<< "$CFLAGS"
IFS=' ' read -ra LDFLAGS_ARRAY <<< "$LDFLAGS"

# Build meson-compatible arrays
CFLAGS_MESON=$(printf "'%s', " "${CFLAGS_ARRAY[@]}" | sed 's/, $//')
LDFLAGS_MESON=$(printf "'%s', " "${LDFLAGS_ARRAY[@]}" | sed 's/, $//')

cat > "$CROSS_FILE" << EOF
[binaries]
c = '$CC'
ar = '$AR'
strip = '$STRIP'
pkgconfig = 'pkg-config'

[host_machine]
system = 'linux'
cpu_family = '$(if [[ "$TARGET_TRIPLE" == armv7a* ]]; then echo "arm"; else echo "aarch64"; fi)'
cpu = '$(if [[ "$TARGET_TRIPLE" == armv7a* ]]; then echo "armv7a"; else echo "aarch64"; fi)'
endian = 'little'

[properties]
c_args = [$CFLAGS_MESON]
c_link_args = [$LDFLAGS_MESON]
EOF

cd "$SRC_DIR"

log_cmd meson setup \
  --cross-file="$CROSS_FILE" \
  --prefix="$INSTALL_DIR" \
  --libdir=lib \
  --default-library=static \
  -Dqrtr-ns=disabled \
  "$MESON_BUILD_DIR"

log "Step 4: Building $TOOL_NAME..."
log_cmd ninja -C "$MESON_BUILD_DIR" -j"$PARALLEL_JOBS"

log "Step 5: Installing $TOOL_NAME..."
log_cmd ninja -C "$MESON_BUILD_DIR" install

log "Step 6: Verifying installation..."
if [ ! -f "$INSTALL_DIR/lib/libqrtr.a" ]; then
  log "ERROR: libqrtr.a not found"
  exit 1
fi

if [ ! -f "$INSTALL_DIR/include/libqrtr.h" ]; then
  log "ERROR: libqrtr.h not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
