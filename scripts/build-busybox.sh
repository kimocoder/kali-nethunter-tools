#!/bin/bash
# build-busybox.sh - Build busybox for Android
# This script downloads, configures, and builds busybox for cross-compilation to Android

set -euo pipefail

# Source environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

# ============================================================================
# Tool Configuration
# ============================================================================
TOOL_NAME="busybox"
TOOL_VERSION="1.38.0"
TOOL_DEPS=()  # No dependencies
TOOL_CONFIGURE_OPTS="--enable-static"
TOOL_PATCHES=()  # Patches manually applied to source

# ============================================================================
# Directories
# ============================================================================
BUILD_DIR="$SCRIPT_DIR/build/$TOOL_NAME"
SRC_DIR="$SCRIPT_DIR/../src/$TOOL_NAME"
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
log "Step 1: Using busybox source from $SRC_DIR..."

if [ ! -d "$SRC_DIR" ]; then
  log "ERROR: Source directory not found: $SRC_DIR"
  log "Please ensure busybox source is in src/busybox"
  exit 1
fi

cd "$SRC_DIR"

# ============================================================================
# Apply Patches
# ============================================================================
log "Step 2: Applying patches..."

for patch in "${TOOL_PATCHES[@]}"; do
  if [ -f "$SCRIPT_DIR/../patches/$patch" ]; then
    # Check if patch is already applied
    if patch -p1 --dry-run -R < "$SCRIPT_DIR/../patches/$patch" >/dev/null 2>&1; then
      log "Patch $patch already applied, skipping"
    else
      log "Applying patch: $patch"
      patch -p1 < "$SCRIPT_DIR/../patches/$patch" 2>&1 | tee -a "$LOG_FILE" || {
        log "WARNING: Patch application had issues (continuing)"
      }
    fi
  fi
done

# ============================================================================
# Configure (busybox uses make config)
# ============================================================================
log "Step 3: Configuring $TOOL_NAME..."

# Clean previous build
log_cmd make distclean || true

# Use Android NDK defconfig
log_cmd make CC="$CC" android_ndk_defconfig

# Enable static linking
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
sed -i 's/# CONFIG_STATIC_LIBGCC is not set/CONFIG_STATIC_LIBGCC=y/' .config

# Set CROSS_COMPILER_PREFIX to empty since we're using CC directly
sed -i 's/CONFIG_CROSS_COMPILER_PREFIX=".*"/CONFIG_CROSS_COMPILER_PREFIX=""/' .config

# Disable TC (traffic control) - missing kernel headers on Android
sed -i 's/^CONFIG_TC=y/# CONFIG_TC is not set/' .config

# Set the sysroot
sed -i "s|CONFIG_SYSROOT=\".*\"|CONFIG_SYSROOT=\"$SYSROOT\"|" .config

# Remove -lgcc since we're using clang (it uses compiler-rt instead)
sed -i 's/CONFIG_EXTRA_LDLIBS=".*"/CONFIG_EXTRA_LDLIBS=""/' .config

# Disable platform functions that conflict with Android libc
sed -i 's/CONFIG_PLATFORM_LINUX=y/# CONFIG_PLATFORM_LINUX is not set/' .config

# Enable verbose resolution errors for debugging
sed -i 's/# CONFIG_VERBOSE_RESOLUTION_ERRORS is not set/CONFIG_VERBOSE_RESOLUTION_ERRORS=y/' .config

# Enable IPv4 preference
sed -i 's/# CONFIG_FEATURE_PREFER_IPV4_ADDRESS is not set/CONFIG_FEATURE_PREFER_IPV4_ADDRESS=y/' .config

# ============================================================================
# Build
# ============================================================================
log "Step 4: Building $TOOL_NAME..."

log_cmd make \
  CC="$CC" \
  CFLAGS="$CFLAGS -DHAVE_STRCHRNUL" \
  LDFLAGS="$LDFLAGS -static" \
  -j"$PARALLEL_JOBS"

# ============================================================================
# Install
# ============================================================================
log "Step 5: Installing $TOOL_NAME..."

# Create install directories
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/include"
mkdir -p "$INSTALL_DIR/lib"

# Copy binary
if [ -f busybox ]; then
  log_cmd cp busybox "$INSTALL_DIR/bin/"
  log_cmd "$STRIP" "$INSTALL_DIR/bin/busybox"
else
  log "ERROR: busybox binary not found after build"
  exit 1
fi

# ============================================================================
# Verify Installation
# ============================================================================
log "Step 6: Verifying installation..."

if [ ! -f "$INSTALL_DIR/bin/busybox" ]; then
  log "ERROR: busybox executable not found in $INSTALL_DIR/bin"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"

# Create marker file
touch "$INSTALL_DIR/.built"

log "Build log saved to: $LOG_FILE"
