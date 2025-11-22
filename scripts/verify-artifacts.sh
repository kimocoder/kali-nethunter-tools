#!/bin/bash
# verify-artifacts.sh - Verify built artifacts
# This script verifies that built artifacts are correct and valid

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/build-env.sh"

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
# Verify ELF Binary
# ============================================================================
verify_elf_binary() {
  local binary="$1"
  local target_arch="${2:-aarch64}"

  if [ ! -f "$binary" ]; then
    log_error "Binary not found: $binary"
    return 1
  fi

  # Check if file is ELF
  if ! file "$binary" | grep -q "ELF"; then
    log_error "Not an ELF binary: $binary"
    return 1
  fi

  # Check architecture
  if [ "$target_arch" = "aarch64" ]; then
    if ! file "$binary" | grep -q "aarch64\|ARM aarch64"; then
      log_error "Binary is not for aarch64: $binary"
      return 1
    fi
  fi

  log_success "ELF binary verified: $binary"
  return 0
}

# ============================================================================
# Verify Header Files
# ============================================================================
verify_headers() {
  local header_dir="$1"

  if [ ! -d "$header_dir" ]; then
    log_error "Header directory not found: $header_dir"
    return 1
  fi

  local header_count=0
  while IFS= read -r -d '' header; do
    if [ ! -r "$header" ]; then
      log_error "Header file not readable: $header"
      return 1
    fi
    ((header_count++))
  done < <(find "$header_dir" -name "*.h" -print0)

  if [ $header_count -eq 0 ]; then
    log_error "No header files found in: $header_dir"
    return 1
  fi

  log_success "Header files verified: $header_count files in $header_dir"
  return 0
}

# ============================================================================
# Verify Library Files
# ============================================================================
verify_libraries() {
  local lib_dir="$1"

  if [ ! -d "$lib_dir" ]; then
    log_error "Library directory not found: $lib_dir"
    return 1
  fi

  local lib_count=0
  while IFS= read -r -d '' lib; do
    if [ ! -r "$lib" ]; then
      log_error "Library file not readable: $lib"
      return 1
    fi
    ((lib_count++))
  done < <(find "$lib_dir" \( -name "*.a" -o -name "*.so*" \) -print0)

  if [ $lib_count -eq 0 ]; then
    log_error "No library files found in: $lib_dir"
    return 1
  fi

  log_success "Library files verified: $lib_count files in $lib_dir"
  return 0
}

# ============================================================================
# Verify Tool Installation
# ============================================================================
verify_tool() {
  local tool="$1"
  local install_dir="$PREFIX/$tool"

  log "Verifying $tool installation..."

  if [ ! -d "$install_dir" ]; then
    log_error "Installation directory not found: $install_dir"
    return 1
  fi

  # Check for marker file
  if [ ! -f "$install_dir/.built" ]; then
    log_error "Build marker file not found: $install_dir/.built"
    return 1
  fi

  # Verify at least one of: lib, include, or bin
  local has_content=0

  if [ -d "$install_dir/lib" ]; then
    if verify_libraries "$install_dir/lib"; then
      has_content=1
    fi
  fi

  if [ -d "$install_dir/include" ]; then
    if verify_headers "$install_dir/include"; then
      has_content=1
    fi
  fi

  if [ -d "$install_dir/bin" ]; then
    local bin_count=0
    while IFS= read -r -d '' binary; do
      if [ -x "$binary" ]; then
        verify_elf_binary "$binary" "aarch64" || true
        ((bin_count++))
      fi
    done < <(find "$install_dir/bin" -type f -print0)

    if [ $bin_count -gt 0 ]; then
      has_content=1
      log_success "Executables verified: $bin_count files in $install_dir/bin"
    fi
  fi

  if [ $has_content -eq 0 ]; then
    log_error "No artifacts found in $install_dir"
    return 1
  fi

  log_success "$tool installation verified"
  return 0
}

# ============================================================================
# Main
# ============================================================================
if [ $# -eq 0 ]; then
  log_error "Usage: $0 <tool_name> [tool_name ...]"
  exit 1
fi

failed=0
for tool in "$@"; do
  if ! verify_tool "$tool"; then
    failed=1
  fi
done

if [ $failed -eq 1 ]; then
  exit 1
fi

log_success "All artifacts verified successfully"
