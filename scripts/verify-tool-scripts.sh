#!/bin/bash
# verify-tool-scripts.sh - Verify tool scripts follow conventions
# This script verifies that tool scripts don't contain hardcoded NDK paths

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# Logging
# ============================================================================
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_success() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $*"
}

# ============================================================================
# Verify Tool Script Independence
# ============================================================================
verify_tool_script() {
  local script="$1"
  local tool_name=$(basename "$script" .sh | sed 's/build-//')

  log "Verifying $script..."

  # Check if script sources build-env.sh
  if ! grep -q "source.*build-env.sh" "$script"; then
    log_error "$script does not source build-env.sh"
    return 1
  fi

  # Check for hardcoded NDK paths
  if grep -q "/home/.*Android/Sdk/ndk" "$script"; then
    log_error "$script contains hardcoded NDK path"
    return 1
  fi

  # Check for hardcoded API levels
  if grep -q "API=.*[0-9]" "$script" | grep -v "API_LEVEL\|API=\""; then
    log_error "$script may contain hardcoded API level"
    return 1
  fi

  # Check for hardcoded target triples
  if grep -q "aarch64-linux-android" "$script" | grep -v "TARGET_TRIPLE"; then
    log_error "$script may contain hardcoded target triple"
    return 1
  fi

  # Check that environment variables are used
  if ! grep -q "\$CC\|\$CXX\|\$AR\|\$RANLIB" "$script"; then
    log_error "$script does not use environment variables for toolchain"
    return 1
  fi

  log_success "$script follows independence conventions"
  return 0
}

# ============================================================================
# Main
# ============================================================================
log "Verifying tool script independence..."

local failed=0
for script in "$SCRIPT_DIR"/build-*.sh; do
  if [ -f "$script" ]; then
    if ! verify_tool_script "$script"; then
      failed=1
    fi
  fi
done

if [ $failed -eq 1 ]; then
  log_error "Tool script verification failed"
  exit 1
fi

log_success "All tool scripts verified"
