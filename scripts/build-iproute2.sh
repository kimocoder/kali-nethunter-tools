#!/bin/bash
# build-iproute2.sh - Build iproute2 (network configuration utilities) for Android
# This script configures and builds iproute2 for cross-compilation to Android

set -euo pipefail

# Source environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

# ============================================================================
# Tool Configuration
# ============================================================================
TOOL_NAME="iproute2"
TOOL_VERSION="5.19.0"
TOOL_DEPS=("libmnl")
TOOL_PATCHES=("iproute2-android.patch")

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
SRC_DIR="$SCRIPT_DIR/../src/$TOOL_NAME"
INSTALL_DIR="$PREFIX/$TOOL_NAME"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$(readlink -f "$LOG_DIR")/build-$TOOL_NAME-$(date +%s).log"

mkdir -p "$INSTALL_DIR" "$LOG_DIR"

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
log "Step 1: Using iproute2 source from $SRC_DIR..."

if [ ! -d "$SRC_DIR" ]; then
  log "ERROR: Source directory not found: $SRC_DIR"
  log "Please ensure iproute2 source is in src/iproute2"
  exit 1
fi

cd "$SRC_DIR"

# ============================================================================
# Apply Patches
# ============================================================================
log "Step 2: Applying patches..."

for patch in "${TOOL_PATCHES[@]}"; do
  PATCH_FILE="$SCRIPT_DIR/../patches/$patch"
  if [ -f "$PATCH_FILE" ]; then
    log "Applying patch: $patch"
    patch -p1 < "$PATCH_FILE" || log "Patch already applied or failed (continuing)"
  else
    log "WARNING: Patch file not found: $PATCH_FILE"
  fi
done

# ============================================================================
# Configure
# ============================================================================
log "Step 3: Configuring $TOOL_NAME..."

# Clean previous build thoroughly
if [ -f config.mk ]; then
  log_cmd make clean || true
  rm -f config.mk
fi

# Remove all object files and archives to prevent cross-arch contamination
find . -name "*.o" -type f -delete 2>/dev/null || true
find . -name "*.a" -type f -delete 2>/dev/null || true
find . -name "*.so" -type f -delete 2>/dev/null || true

# Run configure script
log_cmd ./configure \
  --prefix="$INSTALL_DIR" \
  --libbpf_force=off

# Android compatibility flags (include -fno-emulated-tls for ARM64 TLS alignment fix)
# Also use initial-exec TLS model which has better alignment
ANDROID_CFLAGS="-D__ANDROID__ -Din_addr_t=uint32_t -D_GNU_SOURCE -DCONF_COLOR=COLOR_OPT_NEVER -fno-emulated-tls -ftls-model=initial-exec"

# Manually disable features not available on Android
sed -i 's/HAVE_ELF:=y/HAVE_ELF:=n/' config.mk
sed -i '/-lelf/d' config.mk
sed -i '/-DHAVE_ELF/d' config.mk
sed -i 's/HAVE_SELINUX:=y/HAVE_SELINUX:=n/' config.mk
sed -i '/-lselinux/d' config.mk
sed -i '/-DHAVE_SELINUX/d' config.mk
sed -i 's/HAVE_RPC:=y/HAVE_RPC:=n/' config.mk
sed -i '/-ltirpc/d' config.mk
sed -i '/-DHAVE_RPC/d' config.mk
sed -i 's/HAVE_CAP:=y/HAVE_CAP:=n/' config.mk
sed -i '/-lcap/d' config.mk
sed -i '/-DHAVE_LIBCAP/d' config.mk
# Add Android compatibility defines
echo "CFLAGS += $ANDROID_CFLAGS -I$PREFIX/libmnl/include" >> config.mk
echo "LDFLAGS += -L$PREFIX/libmnl/lib" >> config.mk

# ============================================================================
# Build
# ============================================================================
log "Step 4: Building $TOOL_NAME..."

# Build with cross-compilation flags
# Set up pkg-config path for libmnl
export PKG_CONFIG_PATH="$PREFIX/libmnl/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

# Override page size to 64KB for ARM64 TLS alignment fix
if [ "$TARGET_ARCH" = "arm64" ]; then
  IPROUTE2_LDFLAGS="${LDFLAGS/-Wl,-z,max-page-size=16384/-Wl,-z,max-page-size=65536,-z,common-page-size=65536} -static -L$PREFIX/libmnl/lib -ldl"
else
  IPROUTE2_LDFLAGS="$LDFLAGS -static -L$PREFIX/libmnl/lib -ldl"
fi

log_cmd make \
  CC="$CC" \
  AR="$AR" \
  EXTRA_CFLAGS="$ANDROID_CFLAGS -I$PREFIX/libmnl/include" \
  LDFLAGS="$IPROUTE2_LDFLAGS" \
  SHARED_LIBS=n \
  SUBDIRS="lib ip tc bridge" \
  -j"$PARALLEL_JOBS"

# ============================================================================
# Install
# ============================================================================
log "Step 5: Installing $TOOL_NAME..."

# Install to our prefix
log_cmd make install \
  DESTDIR="" \
  PREFIX="$INSTALL_DIR" \
  SBINDIR="$INSTALL_DIR/bin"

# Strip binaries
log "Stripping binaries..."
find "$INSTALL_DIR/bin" -type f -executable -exec "$STRIP" {} \; 2>/dev/null || true

# Fix TLS alignment for ARM64 (Android Bionic requires 64-byte alignment)
if [ "$TARGET_ARCH" = "arm64" ]; then
  log "Fixing TLS alignment for ARM64..."
  for binary in "$INSTALL_DIR/bin"/*; do
    if [ -f "$binary" ] && [ -x "$binary" ]; then
      python3 "$SCRIPT_DIR/fix-tls-alignment.py" "$binary" 2>&1 | tee -a "$LOG_FILE" || log "Warning: TLS fix failed for $(basename $binary)"
    fi
  done
fi

# ============================================================================
# Verify Installation
# ============================================================================
log "Step 6: Verifying installation..."

if [ ! -f "$INSTALL_DIR/bin/ip" ]; then
  log "ERROR: ip executable not found in $INSTALL_DIR/bin"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
log "Installed binaries:"
ls -lh "$INSTALL_DIR/bin/" | tee -a "$LOG_FILE"

# Create marker file
touch "$INSTALL_DIR/.built"

log "Build log saved to: $LOG_FILE"
