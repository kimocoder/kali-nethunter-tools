#!/bin/bash
# build-qca-monitor.sh - Build qca-monitor (Qualcomm Monitor Mode Tool) for Android

set -euo pipefail

# Source environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-env.sh"

# ============================================================================
# Tool Configuration
# ============================================================================
TOOL_NAME="qca-monitor"
TOOL_VERSION="1.0"
TOOL_DEPS=()
TOOL_PATCHES=()

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
log "Step 1: Using qca-monitor source from $SRC_DIR..."

if [ ! -d "$SRC_DIR" ]; then
  log "ERROR: Source directory not found: $SRC_DIR"
  log "Please ensure qca-monitor source is in src/qca-monitor"
  exit 1
fi

cd "$SRC_DIR"

# ============================================================================
# Build
# ============================================================================
log "Step 2: Building $TOOL_NAME..."

# Create bin directory
mkdir -p bin

# Compile the tool
log "Compiling qca_monitor..."
log_cmd "$CXX" \
  -std=c++11 \
  -O2 \
  -fPIE \
  -pie \
  $CXXFLAGS \
  -D__ANDROID__ \
  -DANDROID \
  qca_monitor.cpp \
  qca_monitor_impl.cpp \
  -o bin/qca-monitor \
  -static-libstdc++

# ============================================================================
# Install
# ============================================================================
log "Step 3: Installing $TOOL_NAME..."

mkdir -p "$INSTALL_DIR/bin"
cp bin/qca-monitor "$INSTALL_DIR/bin/"

# Strip binary
log "Stripping binary..."
"$STRIP" "$INSTALL_DIR/bin/qca-monitor" 2>/dev/null || true

# Fix TLS alignment for ARM64
if [ "$TARGET_ARCH" = "arm64" ]; then
  log "Fixing TLS alignment for ARM64..."
  python3 "$SCRIPT_DIR/fix-tls-alignment.py" "$INSTALL_DIR/bin/qca-monitor" 2>&1 | tee -a "$LOG_FILE" || log "Warning: TLS fix failed"
fi

# ============================================================================
# Verify Installation
# ============================================================================
log "Step 4: Verifying installation..."

if [ ! -f "$INSTALL_DIR/bin/qca-monitor" ]; then
  log "ERROR: qca-monitor executable not found in $INSTALL_DIR/bin"
  exit 1
fi

log "SUCCESS: $TOOL_NAME built and installed to $INSTALL_DIR"
log "Installed binary:"
ls -lh "$INSTALL_DIR/bin/qca-monitor" | tee -a "$LOG_FILE"

# Create marker file
touch "$INSTALL_DIR/.built"

log "Build log saved to: $LOG_FILE"
