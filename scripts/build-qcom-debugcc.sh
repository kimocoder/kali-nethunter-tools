#!/bin/bash
# build-qcom-debugcc.sh - Build Qualcomm Debug Clock Controller for Android

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

TOOL_NAME="qcom-debugcc"
TOOL_VERSION="master"
TOOL_DEPS=()
TOOL_CONFIGURE_OPTS=""
TOOL_PATCHES=()

BUILD_DIR="$SCRIPT_DIR/../build/$TOOL_NAME"
SRC_DIR="$BUILD_DIR/src/debugcc-src"
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

log "Step 1: Preparing $TOOL_NAME source..."

# Check for local source
if [ -d "$SCRIPT_DIR/../src/qcom-debugcc" ] && [ ! -d "$SRC_DIR" ]; then
  log "Using local qcom-debugcc source..."
  mkdir -p "$BUILD_DIR/src"
  cp -r "$SCRIPT_DIR/../src/qcom-debugcc" "$SRC_DIR"
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

log "Step 3: Configuring $TOOL_NAME with meson..."

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

# Create cross-compilation file for meson
cat > android-cross.txt << EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
strip = '$STRIP'

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
  --buildtype=release

log "Step 4: Building $TOOL_NAME..."
log_cmd meson compile -C _build -j"$PARALLEL_JOBS"

log "Step 5: Installing $TOOL_NAME..."
log_cmd meson install -C _build

log "Step 6: Verifying installation..."
if [ ! -f "$INSTALL_DIR/bin/debugcc" ]; then
  log "ERROR: debugcc binary not found"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
touch "$INSTALL_DIR/.built"
log "Build log saved to: $LOG_FILE"
