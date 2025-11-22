#!/bin/bash
# build.sh - Main Orchestrator for Android Cross-Compilation Build System
# This script orchestrates the building of all tools in dependency order

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================
# Handle both sourced and executed contexts (including compiled binaries)
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
TOOLS_CONF="$SCRIPT_DIR/tools.conf"
BUILD_CONF="$SCRIPT_DIR/build.conf"
VERSION_FILE="$SCRIPT_DIR/version"
VERSION_URL="https://raw.githubusercontent.com/kimocoder/kali-nethunter-tools/refs/heads/master/version"

# ============================================================================
# Global Variables
# ============================================================================
declare -A TOOLS_VERSION
declare -A TOOLS_DEPS
declare -A TOOLS_CONFIGURE_OPTS
declare -A TOOLS_PATCHES
declare -A TOOLS_BUILD_TYPE
declare -A TOOLS_IS_LIBRARY
declare -a TOOLS_LIST
declare -a BUILD_ORDER

VERBOSE="${VERBOSE:-0}"
ARCH_FILTER=""
COMMAND=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      COMMAND="help"
      shift
      ;;
    -v|--verbose)
      VERBOSE=1
      shift
      ;;
    --arch)
      ARCH_FILTER="$2"
      shift 2
      ;;
    build|clean|rebuild|list|status|push|upgrade|update|check|shell|log|help)
      if [ -z "$COMMAND" ]; then
        COMMAND="$1"
      fi
      shift
      ;;
    --update)
      COMMAND="update"
      shift
      ;;
    *)
      break
      ;;
  esac
done

# Default to help if no command provided
if [ -z "$COMMAND" ]; then
  COMMAND="help"
fi

# ============================================================================
# Logging Functions
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
# Parse build.conf
# ============================================================================
parse_build_conf() {
  if [ ! -f "$BUILD_CONF" ]; then
    log "build.conf not found, using defaults"
    return 0
  fi

  source "$BUILD_CONF" || {
    log_error "Failed to parse build.conf"
    exit 1
  }

  if [ "$VERBOSE" = "1" ]; then
    log "Loaded build configuration from $BUILD_CONF"
  fi
}

# ============================================================================
# Parse tools.conf
# ============================================================================
parse_tools_conf() {
  if [ ! -f "$TOOLS_CONF" ]; then
    log_error "tools.conf not found at $TOOLS_CONF"
    exit 1
  fi

  while IFS='|' read -r name version deps opts patches build_type is_library; do
    # Skip comments and empty lines
    [[ "$name" =~ ^#.*$ ]] && continue
    [[ -z "$name" ]] && continue

    TOOLS_LIST+=("$name")
    TOOLS_VERSION["$name"]="$version"
    TOOLS_DEPS["$name"]="$deps"
    TOOLS_CONFIGURE_OPTS["$name"]="$opts"
    TOOLS_PATCHES["$name"]="$patches"
    TOOLS_BUILD_TYPE["$name"]="${build_type:-autotools}"
    TOOLS_IS_LIBRARY["$name"]="${is_library:-no}"

    if [ "$VERBOSE" = "1" ]; then
      log "Loaded tool: $name (v$version, deps: $deps, build: ${build_type:-autotools}, library: ${is_library:-no})"
    fi
  done < "$TOOLS_CONF"
}

# ============================================================================
# Topological Sort (Dependency Resolution)
# ============================================================================
topological_sort() {
  local -a sorted
  local -a visited
  local -a visiting

  local visit_node
  visit_node() {
    local node="$1"
    
    # Check for cycles
    for v in "${visiting[@]:-}"; do
      if [ "$v" = "$node" ]; then
        log_error "Circular dependency detected involving $node"
        exit 1
      fi
    done

    # Skip if already visited
    for v in "${visited[@]:-}"; do
      if [ "$v" = "$node" ]; then
        return 0
      fi
    done

    visiting+=("$node")

    # Visit dependencies first
    local deps="${TOOLS_DEPS[$node]}"
    if [ -n "$deps" ]; then
      IFS=',' read -ra dep_array <<< "$deps"
      for dep in "${dep_array[@]}"; do
        dep=$(echo "$dep" | xargs)  # Trim whitespace
        if [ -n "$dep" ]; then
          visit_node "$dep"
        fi
      done
    fi

    visiting=("${visiting[@]/$node}")
    visited+=("$node")
    sorted+=("$node")
  }

  for tool in "${TOOLS_LIST[@]}"; do
    visit_node "$tool"
  done

  BUILD_ORDER=("${sorted[@]}")
}

# ============================================================================
# Build Tool
# ============================================================================
build_tool() {
  local tool="$1"
  local build_script="$SCRIPT_DIR/scripts/build-$tool.sh"

  if [ ! -f "$build_script" ]; then
    log_error "Build script not found: $build_script"
    return 1
  fi

  log "Building $tool..."
  
  if (cd "$SCRIPT_DIR" && bash "$build_script"); then
    log_success "$tool built successfully"
    return 0
  else
    log_error "$tool build failed"
    return 1
  fi
}

# ============================================================================
# Clean Tool
# ============================================================================
clean_tool() {
  local tool="$1"
  local build_dir="$SCRIPT_DIR/build/$tool"
  local install_dir="$SCRIPT_DIR/out/${TARGET_TRIPLE:-aarch64-linux-android}/$tool"
  local src_dir="$SCRIPT_DIR/src/$tool"

  log "Cleaning $tool..."

  # Remove build directory
  if [ -d "$build_dir" ]; then
    rm -rf "$build_dir"
    log "Removed build directory: $build_dir"
  fi

  # Remove install directory
  if [ -d "$install_dir" ]; then
    rm -rf "$install_dir"
    log "Removed install directory: $install_dir"
  fi

  # Clean object files and build artifacts from source directory
  if [ -d "$src_dir" ]; then
    log "Cleaning build artifacts from source: $src_dir"
    
    # Remove object files
    find "$src_dir" -type f -name "*.o" -delete 2>/dev/null || true
    
    # Remove static libraries
    find "$src_dir" -type f -name "*.a" -delete 2>/dev/null || true
    
    # Remove shared libraries
    find "$src_dir" -type f \( -name "*.so" -o -name "*.so.*" \) -delete 2>/dev/null || true
    
    # Remove dependency files
    find "$src_dir" -type f -name "*.d" -delete 2>/dev/null || true
    
    # Remove CMake build artifacts
    find "$src_dir" -type d -name "CMakeFiles" -exec rm -rf {} + 2>/dev/null || true
    find "$src_dir" -type f -name "CMakeCache.txt" -delete 2>/dev/null || true
    find "$src_dir" -type f -name "cmake_install.cmake" -delete 2>/dev/null || true
    
    # Remove autotools artifacts
    find "$src_dir" -type f -name "*.la" -delete 2>/dev/null || true
    find "$src_dir" -type f -name "*.lo" -delete 2>/dev/null || true
    find "$src_dir" -type d -name ".libs" -exec rm -rf {} + 2>/dev/null || true
    
    log "Source directory cleaned"
  fi
  
  # Clean scripts/build directory for this tool
  local scripts_build_dir="$SCRIPT_DIR/scripts/build/$tool"
  if [ -d "$scripts_build_dir" ]; then
    log "Cleaning scripts/build artifacts: $scripts_build_dir"
    
    # Remove downloaded tarballs
    find "$scripts_build_dir" -type f \( -name "*.tar.gz" -o -name "*.tar.xz" -o -name "*.tar.bz2" -o -name "*.tgz" -o -name "*.zip" \) -delete 2>/dev/null || true
    
    # Remove object files and libraries
    find "$scripts_build_dir" -type f \( -name "*.o" -o -name "*.a" -o -name "*.so" -o -name "*.so.*" -o -name "*.d" -o -name "*.la" -o -name "*.lo" \) -delete 2>/dev/null || true
    
    # Remove CMake and autotools artifacts
    find "$scripts_build_dir" -type d \( -name "CMakeFiles" -o -name ".libs" \) -exec rm -rf {} + 2>/dev/null || true
    find "$scripts_build_dir" -type f -name "CMakeCache.txt" -delete 2>/dev/null || true
    find "$scripts_build_dir" -type f -name "cmake_install.cmake" -delete 2>/dev/null || true
    
    log "Scripts/build directory cleaned"
  fi
}

# ============================================================================
# List Tools
# ============================================================================
list_tools() {
  log "Available tools:"
  
  # Create sorted array of user-facing tools
  local -a user_tools=()
  for tool in "${TOOLS_LIST[@]}"; do
    # Skip libraries (only show user-facing tools)
    if [ "${TOOLS_IS_LIBRARY[$tool]}" = "yes" ]; then
      continue
    fi
    user_tools+=("$tool")
  done
  
  # Sort alphabetically
  IFS=$'\n' sorted_tools=($(sort <<<"${user_tools[*]}"))
  unset IFS
  
  for tool in "${sorted_tools[@]}"; do
    local version="${TOOLS_VERSION[$tool]}"
    local deps="${TOOLS_DEPS[$tool]}"
    local build_type="${TOOLS_BUILD_TYPE[$tool]}"
    
    if [ -z "$deps" ]; then
      deps="(no dependencies)"
    else
      deps="(requires: $deps)"
    fi
    
    printf "  %-15s v%-10s [%s] %s\n" "$tool" "$version" "$build_type" "$deps"
  done
  
  echo ""
  log "Note: Dependencies are built automatically when needed"
}

# ============================================================================
# Show Status
# ============================================================================
show_status() {
  log "Build status:"
  
  # Create sorted array of user-facing tools
  local -a user_tools=()
  for tool in "${TOOLS_LIST[@]}"; do
    # Skip libraries (only show user-facing tools)
    if [ "${TOOLS_IS_LIBRARY[$tool]}" = "yes" ]; then
      continue
    fi
    user_tools+=("$tool")
  done
  
  # Sort alphabetically
  IFS=$'\n' sorted_tools=($(sort <<<"${user_tools[*]}"))
  unset IFS
  
  for tool in "${sorted_tools[@]}"; do
    local install_dir="$SCRIPT_DIR/out/${TARGET_TRIPLE:-aarch64-linux-android}/$tool"
    
    if [ -f "$install_dir/.built" ]; then
      # Check if binary is statically linked
      local static_status="UNKNOWN"
      local binary_path=""
      
      # Look for the main binary in bin/ or sbin/
      if [ -d "$install_dir/bin" ]; then
        for bin in "$install_dir/bin"/*; do
          if [ -f "$bin" ] && [ -x "$bin" ]; then
            binary_path="$bin"
            break
          fi
        done
      fi
      
      if [ -z "$binary_path" ] && [ -d "$install_dir/sbin" ]; then
        for bin in "$install_dir/sbin"/*; do
          if [ -f "$bin" ] && [ -x "$bin" ]; then
            binary_path="$bin"
            break
          fi
        done
      fi
      
      # Check if binary is statically linked using file command
      if [ -n "$binary_path" ]; then
        if file "$binary_path" | grep -q "statically linked"; then
          static_status="YES"
        elif file "$binary_path" | grep -q "dynamically linked"; then
          static_status="NO"
        fi
      fi
      
      printf "  %-15s [BUILT]  [STATIC: %s]\n" "$tool" "$static_status"
    else
      printf "  %-15s [NOT BUILT]\n" "$tool"
    fi
  done
}

# ============================================================================
# Check System
# ============================================================================
run_checks() {
  local errors=0
  local warnings=0
  
  log "Running system checks..."
  echo ""
  
  # ========================================
  # Check 1: Tools.conf vs Build Scripts
  # ========================================
  log "Check 1: Verifying build scripts exist for all tools in tools.conf..."
  
  for tool in "${TOOLS_LIST[@]}"; do
    local build_script="$SCRIPT_DIR/scripts/build-$tool.sh"
    if [ ! -f "$build_script" ]; then
      log_error "  ✗ Missing build script for '$tool': $build_script"
      ((errors++))
    fi
  done
  
  if [ $errors -eq 0 ]; then
    log "  ✓ All tools have build scripts"
  fi
  echo ""
  
  # ========================================
  # Check 2: Source Directory Availability
  # ========================================
  log "Check 2: Checking source directory availability..."
  
  local -a missing_sources=()
  for tool in "${TOOLS_LIST[@]}"; do
    local src_dir="$SCRIPT_DIR/src/$tool"
    # Handle special cases where directory names differ
    case "$tool" in
      libnl3) src_dir="$SCRIPT_DIR/src/libnl" ;;
      openssl) src_dir="$SCRIPT_DIR/src/libssl" ;;
      tshark) src_dir="$SCRIPT_DIR/src/wireshark" ;;
      glib2) src_dir="$SCRIPT_DIR/src/glib2-old-2.9.6" ;;
    esac
    
    if [ ! -d "$src_dir" ]; then
      missing_sources+=("$tool")
      ((warnings++)) || true
    fi
  done
  
  if [ ${#missing_sources[@]} -gt 0 ]; then
    log "  ⚠ No local source for: ${missing_sources[*]} (will download if needed)"
  fi
  
  if [ ${#missing_sources[@]} -eq 0 ]; then
    log "  ✓ All tools have local sources"
  fi
  echo ""
  
  # ========================================
  # Check 3: TLS Alignment for ARM64 Binaries
  # ========================================
  log "Check 3: Checking TLS alignment for ARM64 binaries..."
  
  local arm64_dir="$SCRIPT_DIR/out/aarch64-linux-android"
  if [ ! -d "$arm64_dir" ]; then
    log "  ⚠ No ARM64 binaries found (not built yet)"
    warnings=$((warnings + 1))
  else
    local tls_issues=0
    local checked=0
    
    for tool in "${TOOLS_LIST[@]}"; do
      # Skip libraries
      if [ "${TOOLS_IS_LIBRARY[$tool]}" = "yes" ]; then
        continue
      fi
      
      local install_dir="$arm64_dir/$tool"
      if [ ! -f "$install_dir/.built" ]; then
        continue
      fi
      
      # Check binaries in bin/ and sbin/
      for dir in bin sbin; do
        if [ -d "$install_dir/$dir" ]; then
          for binary in "$install_dir/$dir"/*; do
            if [ -f "$binary" ] && [ -x "$binary" ]; then
              checked=$((checked + 1))
              
              # Check TLS alignment using readelf
              if command -v readelf > /dev/null 2>&1; then
                local tls_align=$(readelf -l "$binary" 2>/dev/null | grep -A 1 "TLS" | grep -oP "0x[0-9a-f]+" | tail -1)
                
                if [ -n "$tls_align" ]; then
                  # Convert hex to decimal
                  local align_dec=$((tls_align))
                  
                  if [ $align_dec -lt 64 ]; then
                    log_error "  ✗ $(basename "$binary") has TLS alignment $align_dec (needs 64)"
                    tls_issues=$((tls_issues + 1))
                    errors=$((errors + 1))
                  fi
                fi
              fi
            fi
          done
        fi
      done
    done
    
    if [ $checked -eq 0 ]; then
      log "  ⚠ No ARM64 binaries found to check"
      warnings=$((warnings + 1))
    elif [ $tls_issues -eq 0 ]; then
      log "  ✓ All $checked ARM64 binaries have correct TLS alignment (64 bytes)"
    else
      log_error "  Found $tls_issues binaries with incorrect TLS alignment"
    fi
  fi
  echo ""
  
  # ========================================
  # Check 4: Dependency Consistency
  # ========================================
  log "Check 4: Verifying dependency consistency..."
  
  local dep_errors=0
  for tool in "${TOOLS_LIST[@]}"; do
    local deps="${TOOLS_DEPS[$tool]}"
    if [ -n "$deps" ]; then
      IFS=',' read -ra dep_array <<< "$deps"
      for dep in "${dep_array[@]}"; do
        dep=$(echo "$dep" | xargs)
        if [ -n "$dep" ] && [[ ! " ${TOOLS_LIST[@]} " =~ " ${dep} " ]]; then
          log_error "  ✗ Tool '$tool' depends on unknown tool '$dep'"
          dep_errors=$((dep_errors + 1))
          errors=$((errors + 1))
        fi
      done
    fi
  done
  
  if [ $dep_errors -eq 0 ]; then
    log "  ✓ All dependencies are valid"
  fi
  echo ""
  
  # ========================================
  # Check 5: Patch Files
  # ========================================
  log "Check 5: Verifying patch files exist..."
  
  local missing_patches=0
  for tool in "${TOOLS_LIST[@]}"; do
    local patches="${TOOLS_PATCHES[$tool]}"
    if [ -n "$patches" ]; then
      IFS=',' read -ra patch_array <<< "$patches"
      for patch in "${patch_array[@]}"; do
        patch=$(echo "$patch" | xargs)
        if [ -n "$patch" ]; then
          local patch_file="$SCRIPT_DIR/patches/$patch"
          if [ ! -f "$patch_file" ]; then
            log_error "  ✗ Missing patch file for '$tool': $patch"
            missing_patches=$((missing_patches + 1))
            errors=$((errors + 1))
          fi
        fi
      done
    fi
  done
  
  if [ $missing_patches -eq 0 ]; then
    log "  ✓ All patch files exist"
  fi
  echo ""
  
  # ========================================
  # Summary
  # ========================================
  echo "========================================"
  log "Check Summary:"
  log "  Errors:   $errors"
  log "  Warnings: $warnings"
  
  if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
    log_success "All checks passed! ✓"
    return 0
  elif [ $errors -eq 0 ]; then
    log "All checks passed with $warnings warning(s)"
    return 0
  else
    log_error "Checks failed with $errors error(s) and $warnings warning(s)"
    return 1
  fi
}

# ============================================================================
# Version Management
# ============================================================================
get_current_version() {
  if [ -f "$VERSION_FILE" ]; then
    cat "$VERSION_FILE"
  else
    echo "unknown"
  fi
}

get_remote_version() {
  local remote_version
  remote_version=$(curl -s -f "$VERSION_URL" 2>/dev/null || echo "")
  
  if [ -z "$remote_version" ]; then
    log_error "Failed to fetch remote version from $VERSION_URL"
    return 1
  fi
  
  echo "$remote_version"
}

compare_versions() {
  local current="$1"
  local remote="$2"
  
  if [ "$current" = "unknown" ]; then
    echo "unknown"
    return 0
  fi
  
  if [ "$current" = "$remote" ]; then
    echo "same"
  else
    # Simple version comparison (works for semantic versioning)
    if [ "$(printf '%s\n' "$current" "$remote" | sort -V | head -n1)" = "$current" ] && [ "$current" != "$remote" ]; then
      echo "outdated"
    else
      echo "newer"
    fi
  fi
}

check_for_updates() {
  local current_version
  local remote_version
  local comparison
  
  current_version=$(get_current_version)
  log "Current version: $current_version"
  
  log "Checking for updates..."
  remote_version=$(get_remote_version)
  
  if [ $? -ne 0 ] || [ -z "$remote_version" ]; then
    log_error "Unable to check for updates. Please check your internet connection."
    return 1
  fi
  
  log "Latest version: $remote_version"
  
  comparison=$(compare_versions "$current_version" "$remote_version")
  
  case "$comparison" in
    same)
      log_success "You are running the latest version!"
      return 0
      ;;
    outdated)
      log "A new version is available: $remote_version (current: $current_version)"
      log "Run '$0 upgrade' to upgrade to the latest version"
      return 2
      ;;
    newer)
      log "You are running a newer version than the remote ($current_version > $remote_version)"
      log "This might be a development version."
      return 0
      ;;
    unknown)
      log "Unable to determine version status (current version unknown)"
      log "Latest available version: $remote_version"
      return 1
      ;;
  esac
}

perform_update() {
  local current_version
  local remote_version
  local comparison
  
  current_version=$(get_current_version)
  log "Current version: $current_version"
  
  log "Checking for updates..."
  remote_version=$(get_remote_version)
  
  if [ $? -ne 0 ] || [ -z "$remote_version" ]; then
    log_error "Unable to check for updates. Please check your internet connection."
    return 1
  fi
  
  log "Latest version: $remote_version"
  
  comparison=$(compare_versions "$current_version" "$remote_version")
  
  if [ "$comparison" = "same" ]; then
    log_success "You are already running the latest version ($current_version)"
    return 0
  fi
  
  if [ "$comparison" = "newer" ]; then
    log "You are running a newer version ($current_version) than the remote ($remote_version)"
    log "This might be a development version. Skipping upgrade."
    return 0
  fi
  
  log "Updating from $current_version to $remote_version..."
  
  # Check if we're in a git repository
  if [ -d "$SCRIPT_DIR/.git" ]; then
    log "Detected git repository. Pulling latest changes..."
    
    # Save current directory
    local original_dir="$PWD"
    
    # Change to script directory
    cd "$SCRIPT_DIR" || {
      log_error "Failed to change to script directory"
      return 1
    }
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
      log_error "You have uncommitted changes. Please commit or stash them before updating."
      cd "$original_dir"
      return 1
    fi
    
    # Pull latest changes
    log "Pulling from remote repository..."
    if git pull origin master; then
      log_success "Successfully upgraded to version $remote_version"
      
      # Verify version file was upgraded
      local new_version
      new_version=$(get_current_version)
      if [ "$new_version" = "$remote_version" ]; then
        log_success "Version verified: $new_version"
      else
        log "Warning: Version file shows $new_version but expected $remote_version"
      fi
      
      cd "$original_dir"
      return 0
    else
      log_error "Failed to pull upgrade from repository"
      cd "$original_dir"
      return 1
    fi
  else
    log_error "Not a git repository. Please download the latest version manually from:"
    log_error "https://github.com/kimocoder/kali-nethunter-tools"
    return 1
  fi
}

# ============================================================================
# Show Help
# ============================================================================
show_help() {
  local version
  version=$(cat "$VERSION_FILE" 2>/dev/null || echo "unknown")
  
  # Color codes
  local BOLD='\033[1m'
  local CYAN='\033[1;36m'
  local GREEN='\033[1;32m'
  local YELLOW='\033[1;33m'
  local BLUE='\033[1;34m'
  local RESET='\033[0m'
  
  echo ""
  echo -e "${BOLD}${CYAN}Android Cross-Compilation Build System${RESET}"
  echo -e "${GREEN}Copyright (C) 2025, Christian <kimocoder> Bremvaag${RESET}"
  echo -e "${YELLOW}Current version: ${version}${RESET}"
  echo ""
  echo -e "${BOLD}Usage:${RESET} $0 [OPTIONS] [COMMAND] [TOOLS...]"
  echo ""
  echo -e "${BOLD}${BLUE}Commands:${RESET}"
  echo -e "  ${GREEN}build${RESET} [TOOLS...]    Build specified tools (default: all, both architectures)"
  echo -e "                      Dependencies are built automatically when needed"
  echo -e "  ${GREEN}clean${RESET} [TOOLS...]    Clean build artifacts (removes build dirs, install dirs,"
  echo -e "                      and all .o, .a, .so files from source and scripts/build)"
  echo -e "  ${GREEN}rebuild${RESET} [TOOLS...]  Clean and rebuild"
  echo -e "  ${GREEN}list${RESET}                List available tools (libraries are hidden)"
  echo -e "  ${GREEN}status${RESET}              Show build status for tools"
  echo -e "  ${GREEN}check${RESET}               Verify tool configurations, sources, and binary TLS alignment"
  echo -e "  ${GREEN}push${RESET} [TOOLS...]     Push built tools to Android device via ADB"
  echo -e "  ${GREEN}shell${RESET}               Connect to Android device via ADB shell"
  echo -e "  ${GREEN}log${RESET} [MODE]          View Android device logs via ADB logcat"
  echo -e "                      MODE: 1=all logs, 2=kernel only, 3=wireless/networking"
  echo -e "  ${GREEN}update${RESET}              Check if a newer version is available"
  echo -e "  ${GREEN}upgrade${RESET}             Upgrade to the latest version from git repository"
  echo -e "  ${GREEN}help${RESET}                Show this help message"
  echo ""
  echo -e "${BOLD}${BLUE}Options:${RESET}"
  echo -e "  ${YELLOW}-h, --help${RESET}          Show this help message"
  echo -e "  ${YELLOW}-v, --verbose${RESET}       Enable verbose output"
  echo -e "  ${YELLOW}--arch${RESET} ARCH         Build for specific architecture (${CYAN}arm64${RESET}, ${CYAN}arm${RESET}, or ${CYAN}both${RESET})"
  echo -e "                      ${CYAN}arm64${RESET}: 64-bit ARM (aarch64-linux-android)"
  echo -e "                      ${CYAN}arm${RESET}: 32-bit ARM (armv7a-linux-androideabi)"
  echo -e "                      ${CYAN}both${RESET}: Build for both architectures (default)"
  echo ""
  echo -e "${BOLD}${BLUE}Examples:${RESET}"
  echo -e "  $0                              ${RESET}# Show help"
  echo -e "  $0 build                        ${RESET}# Build all tools for both architectures"
  echo -e "  $0 build --arch arm64           ${RESET}# Build all tools for ARM64 only"
  echo -e "  $0 build --arch arm iw          ${RESET}# Build iw for ARM (32-bit) only"
  echo -e "  $0 build aircrack-ng tshark     ${RESET}# Build aircrack-ng and tshark (dependencies auto-built)"
  echo -e "  $0 rebuild --arch arm64 tshark  ${RESET}# Rebuild tshark for ARM64 only"
  echo -e "  $0 clean                        ${RESET}# Clean all artifacts (both architectures)"
  echo -e "  $0 list                         ${RESET}# List available tools"
  echo -e "  $0 push iw tcpdump              ${RESET}# Push to device (auto-detects architecture)"
  echo -e "  $0 shell                        ${RESET}# Connect to device shell"
  echo -e "  $0 log 3                        ${RESET}# View wireless/networking logs"
  echo -e "  $0 update                       ${RESET}# Check if updates are available"
  echo -e "  $0 upgrade                      ${RESET}# Upgrade to latest version"
  echo ""
  echo -e "${BOLD}${BLUE}Environment Variables:${RESET}"
  echo -e "  ${YELLOW}ANDROID_NDK_HOME${RESET}    Path to Android NDK (required)"
  echo -e "  ${YELLOW}VERBOSE${RESET}             Set to 1 for verbose output"
  echo -e "  ${YELLOW}PARALLEL_JOBS${RESET}       Number of parallel build jobs (default: nproc)"
  echo ""
  echo -e "${BOLD}${BLUE}Configuration Files:${RESET}"
  echo -e "  ${CYAN}build.conf${RESET}          Current active configuration (symlink)"
  echo -e "  ${CYAN}build-arm64.conf${RESET}    ARM64 (64-bit) configuration"
  echo -e "  ${CYAN}build-arm.conf${RESET}      ARM (32-bit) configuration"
}

# ============================================================================
# Architecture Handling
# ============================================================================
get_architectures() {
  case "${ARCH_FILTER:-both}" in
    arm64)
      echo "arm64"
      ;;
    arm)
      echo "arm"
      ;;
    both|"")
      echo "arm64 arm"
      ;;
    *)
      log_error "Unknown architecture: $ARCH_FILTER"
      log_error "Valid options: arm64, arm, both"
      exit 1
      ;;
  esac
}

setup_architecture() {
  local arch="$1"
  local config_file=""
  
  case "$arch" in
    arm64)
      config_file="build-arm64.conf"
      ;;
    arm)
      config_file="build-arm.conf"
      ;;
    *)
      log_error "Unknown architecture: $arch"
      exit 1
      ;;
  esac
  
  if [ ! -f "$SCRIPT_DIR/$config_file" ]; then
    log_error "Configuration file not found: $config_file"
    exit 1
  fi
  
  # Create symlink to architecture-specific config
  ln -sf "$config_file" "$SCRIPT_DIR/build.conf"
  
  log "Configured for architecture: $arch ($config_file)"
}

detect_device_architecture() {
  local device_abi
  device_abi=$(adb shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r')
  
  case "$device_abi" in
    arm64-v8a|aarch64)
      echo "arm64"
      ;;
    armeabi-v7a|armeabi)
      echo "arm"
      ;;
    *)
      log_error "Unsupported or unknown device architecture: $device_abi"
      log_error "Please specify architecture with --arch"
      exit 1
      ;;
  esac
}

# ============================================================================
# Main Build Logic
# ============================================================================
main() {
  # Special handling for push command - detect device architecture
  if [ "$COMMAND" = "push" ] && [ -z "$ARCH_FILTER" ]; then
    log "Detecting device architecture..."
    ARCH_FILTER=$(detect_device_architecture)
    log "Device architecture: $ARCH_FILTER"
  fi
  
  # Get list of architectures to build
  local architectures
  architectures=$(get_architectures)
  
  # If building for multiple architectures, handle recursively
  if [ "$COMMAND" != "list" ] && [ "$COMMAND" != "help" ] && [ "$COMMAND" != "status" ] && [ "$COMMAND" != "update" ] && [ "$COMMAND" != "upgrade" ] && [ "$COMMAND" != "check" ] && [ "$COMMAND" != "shell" ] && [ "$COMMAND" != "log" ]; then
    local arch_count
    arch_count=$(echo "$architectures" | wc -w)
    
    if [ "$arch_count" -gt 1 ]; then
      log "Building for multiple architectures: $architectures"
      local failed_archs=()
      
      for arch in $architectures; do
        log "=========================================="
        log "Building for architecture: $arch"
        log "=========================================="
        
        # Recursively call with specific architecture
        if ! "$0" --arch "$arch" "$COMMAND" "$@"; then
          failed_archs+=("$arch")
        fi
        echo ""
      done
      
      # Summary
      log "=========================================="
      log "Build Summary"
      log "=========================================="
      
      if [ ${#failed_archs[@]} -eq 0 ]; then
        log_success "All architectures completed successfully!"
        exit 0
      else
        log_error "Failed architectures: ${failed_archs[*]}"
        exit 1
      fi
    fi
    
    # Single architecture - setup and continue
    setup_architecture "$architectures"
  fi
  
  # Load configuration
  parse_build_conf
  parse_tools_conf
  
  # Resolve dependency order
  topological_sort

  case "$COMMAND" in
    build)
      local -a tools_to_build
      local -a tools_with_deps
      
      if [ $# -eq 0 ]; then
        # Build all tools in dependency order
        tools_to_build=("${BUILD_ORDER[@]}")
      else
        # Build specified tools and their dependencies
        local -a requested_tools
        for tool in "$@"; do
          if [[ ! " ${TOOLS_LIST[@]} " =~ " ${tool} " ]]; then
            log_error "Unknown tool: $tool"
            exit 1
          fi
          requested_tools+=("$tool")
        done
        
        # Collect all dependencies for requested tools
        local -A needed_tools
        collect_deps() {
          local tool="$1"
          needed_tools["$tool"]=1
          local deps="${TOOLS_DEPS[$tool]}"
          if [ -n "$deps" ]; then
            IFS=',' read -ra dep_array <<< "$deps"
            for dep in "${dep_array[@]}"; do
              dep=$(echo "$dep" | xargs)
              if [ -n "$dep" ] && [ -z "${needed_tools[$dep]:-}" ]; then
                collect_deps "$dep"
              fi
            done
          fi
        }
        
        for tool in "${requested_tools[@]}"; do
          collect_deps "$tool"
        done
        
        # Build in dependency order
        for tool in "${BUILD_ORDER[@]}"; do
          if [ -n "${needed_tools[$tool]:-}" ]; then
            tools_to_build+=("$tool")
          fi
        done
      fi

      log "Building tools in order: ${tools_to_build[*]}"
      
      for tool in "${tools_to_build[@]}"; do
        if ! build_tool "$tool"; then
          log_error "Build failed for: $tool"
          exit 1
        fi
      done

      log_success "All tools built successfully"
      ;;

    clean)
      local -a tools_to_clean
      
      if [ $# -eq 0 ]; then
        tools_to_clean=("${TOOLS_LIST[@]}")
      else
        tools_to_clean=("$@")
      fi

      for tool in "${tools_to_clean[@]}"; do
        clean_tool "$tool"
      done

      # Also clean scripts/build directories
      log "Cleaning scripts/build directories..."
      if [ -d "$SCRIPT_DIR/scripts/build" ]; then
        find "$SCRIPT_DIR/scripts/build" -type f \( -name "*.o" -o -name "*.a" -o -name "*.so" -o -name "*.so.*" -o -name "*.d" -o -name "*.la" -o -name "*.lo" \) -delete 2>/dev/null || true
        find "$SCRIPT_DIR/scripts/build" -type d \( -name ".libs" -o -name "CMakeFiles" \) -exec rm -rf {} + 2>/dev/null || true
        log "Scripts build artifacts cleaned"
      fi

      log_success "Clean completed"
      ;;

    rebuild)
      local -a tools_to_rebuild
      
      if [ $# -eq 0 ]; then
        tools_to_rebuild=("${BUILD_ORDER[@]}")
      else
        tools_to_rebuild=("$@")
      fi

      for tool in "${tools_to_rebuild[@]}"; do
        clean_tool "$tool"
      done

      for tool in "${tools_to_rebuild[@]}"; do
        if ! build_tool "$tool"; then
          log_error "Rebuild failed for $tool"
          exit 1
        fi
      done

      log_success "Rebuild completed successfully"
      ;;

    list)
      list_tools
      ;;

    status)
      show_status
      ;;

    check)
      run_checks
      exit $?
      ;;

    push)
      local -a tools_to_push
      
      if [ $# -eq 0 ]; then
        log_error "Please specify which tools to push"
        log "Usage: $0 push [TOOLS...]"
        exit 1
      fi
      
      # Check if adb is available
      if ! command -v adb > /dev/null 2>&1; then
        log_error "adb command not found. Please install Android SDK platform-tools"
        exit 1
      fi
      
      # Check if device is connected
      if ! adb devices | grep -q "device$"; then
        log_error "No Android device connected. Please connect a device and enable USB debugging"
        exit 1
      fi
      
      tools_to_push=("$@")
      
      log "Pushing tools to Android device at /data/local/tmp/"
      
      local failed_tools=()
      for tool in "${tools_to_push[@]}"; do
        if [[ ! " ${TOOLS_LIST[@]} " =~ " ${tool} " ]]; then
          log_error "Unknown tool: $tool"
          failed_tools+=("$tool")
          continue
        fi
        
        local install_dir="$SCRIPT_DIR/out/${TARGET_TRIPLE}/$tool"
        
        if [ ! -f "$install_dir/.built" ]; then
          log_error "Tool $tool not built yet. Build it first with: $0 build $tool"
          failed_tools+=("$tool")
          continue
        fi
        
        log "Pushing $tool..."
        
        # Push binaries from bin directory
        local has_binaries=false
        if [ -d "$install_dir/bin" ]; then
          for binary in "$install_dir/bin"/*; do
            if [ -f "$binary" ] && [ -x "$binary" ]; then
              has_binaries=true
              local binary_name=$(basename "$binary")
              log "  Pushing $binary_name..."
              if adb push "$binary" /data/local/tmp/ > /dev/null 2>&1; then
                adb shell chmod 755 /data/local/tmp/"$binary_name" 2>/dev/null || true
                log_success "  $binary_name pushed successfully"
              else
                log_error "  Failed to push $binary_name"
                failed_tools+=("$tool")
              fi
            fi
          done
        fi
        
        # Push binaries from sbin directory (for tools like aircrack-ng)
        if [ -d "$install_dir/sbin" ]; then
          for binary in "$install_dir/sbin"/*; do
            if [ -f "$binary" ] && [ -x "$binary" ]; then
              has_binaries=true
              local binary_name=$(basename "$binary")
              log "  Pushing $binary_name..."
              if adb push "$binary" /data/local/tmp/ > /dev/null 2>&1; then
                adb shell chmod 755 /data/local/tmp/"$binary_name" 2>/dev/null || true
                log_success "  $binary_name pushed successfully"
              else
                log_error "  Failed to push $binary_name"
                failed_tools+=("$tool")
              fi
            fi
          done
        fi
        
        if [ "$has_binaries" = false ]; then
          log_error "No binaries found for $tool"
          failed_tools+=("$tool")
        fi
        
        # Push shared libraries (for tools like tshark that need them)
        if [ -d "$install_dir/lib" ]; then
          for lib in "$install_dir/lib"/*.so; do
            if [ -f "$lib" ]; then
              local lib_name=$(basename "$lib")
              log "  Pushing $lib_name..."
              if adb push "$lib" /data/local/tmp/ > /dev/null 2>&1; then
                adb shell chmod 644 /data/local/tmp/"$lib_name" 2>/dev/null || true
                log_success "  $lib_name pushed successfully"
              else
                log_error "  Failed to push $lib_name"
              fi
            fi
          done
        fi
      done
      
      if [ ${#failed_tools[@]} -gt 0 ]; then
        log_error "Failed to push: ${failed_tools[*]}"
        exit 1
      fi
      
      log_success "All tools pushed successfully to /data/local/tmp/"
      
      # Check if tshark was pushed and show usage hint
      for tool in "${tools_to_push[@]}"; do
        if [ "$tool" = "tshark" ]; then
          echo ""
          log "Note: tshark is statically linked and ready to use:"
          echo "  adb shell"
          echo "  cd /data/local/tmp"
          echo "  ./tshark --version"
          echo "  ./tshark -D  # List interfaces"
          echo "  ./tshark -i wlan0  # Capture on wlan0"
          echo ""
          break
        fi
      done
      ;;

    shell)
      # Check if adb is available
      if ! command -v adb > /dev/null 2>&1; then
        log_error "adb command not found. Please install Android SDK platform-tools"
        exit 1
      fi
      
      # Check if device is connected
      if ! adb devices | grep -q "device$"; then
        log_error "No Android device connected. Please connect a device and enable USB debugging"
        exit 1
      fi
      
      log "Connecting to Android device shell..."
      log "Tip: Built tools are located in /data/local/tmp/"
      echo ""
      
      # Connect to adb shell
      adb shell
      ;;

    log)
      # Check if adb is available
      if ! command -v adb > /dev/null 2>&1; then
        log_error "adb command not found. Please install Android SDK platform-tools"
        exit 1
      fi
      
      # Check if device is connected
      if ! adb devices | grep -q "device$"; then
        log_error "No Android device connected. Please connect a device and enable USB debugging"
        exit 1
      fi
      
      local log_mode="${1:-1}"
      
      case "$log_mode" in
        1)
          log "Viewing all Android logs (Ctrl+C to stop)..."
          echo ""
          adb logcat
          ;;
        2)
          log "Viewing kernel logs only (Ctrl+C to stop)..."
          echo ""
          adb logcat -b kernel
          ;;
        3)
          log "Viewing wireless/networking logs (Ctrl+C to stop)..."
          log "Filtering: wifi, wlan, netlink, mac80211, cfg80211, nl80211, wireless"
          echo ""
          adb logcat | grep -iE "wifi|wlan|netlink|mac80211|cfg80211|nl80211|wireless|80211"
          ;;
        *)
          log_error "Invalid log mode: $log_mode"
          echo ""
          echo "Usage: $0 log [MODE]"
          echo ""
          echo "Available modes:"
          echo "  1 - All logs (default)"
          echo "  2 - Kernel logs only"
          echo "  3 - Wireless/networking logs (wifi, netlink, mac80211, cfg80211, etc.)"
          echo ""
          echo "Examples:"
          echo "  $0 log      # View all logs"
          echo "  $0 log 1    # View all logs"
          echo "  $0 log 2    # View kernel logs"
          echo "  $0 log 3    # View wireless/networking logs"
          exit 1
          ;;
      esac
      ;;

    update)
      check_for_updates
      exit $?
      ;;

    upgrade)
      perform_update
      exit $?
      ;;

    help)
      show_help
      ;;

    *)
      log_error "Unknown command: $COMMAND"
      show_help
      exit 1
      ;;
  esac
}

# ============================================================================
# Entry Point
# ============================================================================
main "$@"
