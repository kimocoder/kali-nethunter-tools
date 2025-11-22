# Android Cross-Compilation Build System

**Copyright (C) 2025, Christian "kimocoder" Bremvaag**  
**Version: 1.0.0**

A unified, modular build system for cross-compiling network security, wireless tools and debug to Android (ARM64/ARM32).

## Overview

This build system provides a clean, maintainable architecture for building native Android binaries for both ARM64 and ARM32 architectures. Key features:

- **Multi-architecture support**: Build for ARM64 (aarch64) and ARM32 (armv7a) simultaneously or individually
- **Automatic dependency resolution**: Dependencies are built automatically in the correct order
- **Version management**: Built-in update checking and upgrade functionality
- **ADB integration**: Push built tools directly to Android devices

### Core Components

- **builder**: Main orchestration script with dependency management, multi-arch support, and comprehensive cleaning
- **build-env.sh**: Environment configuration for NDK paths, compiler toolchain, and global flags
- **build-{tool}.sh**: Individual tool-specific build scripts
- **tools.conf**: Declarative tool manifest defining tools, versions, and dependencies
- **build.conf**: Build configuration (symlink to build-arm64.conf or build-arm.conf)

## Quick Start

### Prerequisites

1. **Android NDK** - Tested with NDK r23+ (API 29+)
2. **Build tools**: wget, tar, make, autotools, cmake, gcc
3. **Python tools** (for some libraries): meson, ninja

### Setup

```bash
# Set NDK path
export ANDROID_NDK_HOME=/path/to/android-ndk

# List available tools
./builder list

# Build all tools for both architectures
./builder build

# Build for specific architecture
./builder build --arch arm64    # 64-bit only
./builder build --arch arm      # 32-bit only

# Build specific tools (dependencies auto-built)
./builder build iw tcpdump

# Check build status
./builder status

# Clean all build artifacts
./builder clean

# Push to Android device
./builder push iw tcpdump
```

## Architecture

### Directory Structure

```
.
├── builder                   # Main orchestrator
├── build-env.sh              # Environment configuration (in scripts/)
├── scripts/                  # Tool-specific build scripts
│   ├── build-env.sh          # Environment configuration
│   ├── build-libnl3.sh
│   ├── build-libpcap.sh
│   ├── build-openssl.sh
│   ├── build-aircrack-ng.sh
│   ├── build-reaver.sh
│   ├── build-mdk4.sh
│   └── ... (all tool scripts)
├── tools.conf                # Tool manifest
├── build.conf                # Build configuration
├── verify-artifacts.sh       # Artifact verification
├── verify-tool-scripts.sh    # Tool script validation
├── src/                      # Source code
├── build/                    # Build artifacts (temporary)
├── out/                      # Final output
│   └── aarch64-linux-android/
│       ├── libnl3/
│       ├── libpcap/
│       ├── openssl/
│       ├── aircrack-ng/
│       ├── reaver/
│       ├── mdk4/
│       ├── hcxdumptool/
│       ├── hcxtools/
│       ├── nmap/
│       ├── iw/
│       └── ... (all tools)
├── logs/                     # Build logs
└── patches/                  # Patch files
```

### Dependency Graph

```
Core Libraries (no dependencies):
  libnl3, libpcap, libcap, libnet, openssl, ifaddrs, radiotap

Wireless Tools:
  libnl3 ──────┬─→ iw
               └─→ mdk4 (also needs libpcap)
  
  libpcap ─────┬─→ tcpdump
               ├─→ aircrack-ng (also needs libnet, openssl)
               ├─→ reaver (also needs libnl3)
               ├─→ hcxdumptool (also needs openssl, ifaddrs)
               └─→ hcxtools (also needs openssl)
  
  openssl ─────┬─→ aircrack-ng
               ├─→ hcxdumptool
               └─→ hcxtools

Network Tools:
  nmap, curl (no dependencies)

Utilities:
  busybox, nano, pixiewps, macchanger (no dependencies)
```

## Usage

### Build Commands

```bash
# Build all tools in dependency order
./builder build

# Build specific tools (with dependencies)
./builder build iw libpcap

# Build for specific architecture
./builder build --arch arm64           # 64-bit ARM only
./builder build --arch arm             # 32-bit ARM only
./builder build --arch both            # Both architectures (default)

# Clean all artifacts (removes build dirs, tarballs, .o files)
./builder clean

# Clean specific tool
./builder clean iw

# Rebuild (clean + build)
./builder rebuild

# List available tools
./builder list

# Show build status
./builder status

# Check for updates
./builder update

# Upgrade to latest version
./builder upgrade

# Push tools to Android device via ADB
./builder push iw tcpdump

# Show help
./builder help
```

### Verbose Output

```bash
# Enable verbose logging
VERBOSE=1 ./builder build

# Or use flag
./builder -v build
```

### Parallel Jobs

```bash
# Control number of parallel build jobs
PARALLEL_JOBS=4 ./builder build
```

## Source Management

### Local Sources Priority

All build scripts prioritize local sources in `src/` directory before downloading:

1. **Check existing build** - If already extracted in `scripts/build/TOOL/src/`, use it
2. **Check local source** - If `src/TOOL/` exists, copy it to build directory
3. **Download fallback** - Only download if local source not found

This ensures:
- ✅ Your patches and modifications are preserved
- ✅ No bandwidth wasted on re-downloading
- ✅ Sources can be committed to git
- ✅ Offline building when sources are present

### Populating Local Sources

After first build, copy sources to `src/` for future use:

```bash
# Build once (downloads sources)
./builder build curl

# Copy to local source directory
cp -r scripts/build/curl/src/curl-src src/curl

# Clean and rebuild (now uses local source)
./builder clean curl
./builder build curl  # Uses src/curl
```

## Configuration

### tools.conf

Defines all available tools and their properties:

```
# Format: TOOL_NAME|VERSION|DEPENDENCIES|CONFIGURE_OPTS|PATCHES|BUILD_TYPE|IS_LIBRARY
libnl3|3.7.0||--disable-cli --disable-pthreads|libnl-android-in_addr.patch|autotools|yes
iw|5.16|libnl3|--disable-cli|iw-android.patch|make|no
```

### build.conf

Symlink to architecture-specific configuration:
- `build-arm64.conf` - ARM64 (aarch64-linux-android)
- `build-arm.conf` - ARM32 (armv7a-linux-androideabi)

Customizes build behavior:

```bash
# Global settings
PARALLEL_JOBS=$(nproc)
VERBOSE=0
LOG_DIR=logs

# Target configuration
TARGET_ARCH=arm64
TARGET_TRIPLE=aarch64-linux-android
API_LEVEL=29

# Per-tool overrides
TOOL_CFLAGS_libnl3="-O2 -fPIC -D_GNU_SOURCE"
```

## Tool Build Scripts

Each tool has a dedicated build script following this pattern:

```bash
#!/bin/bash
set -euo pipefail

# Source environment
source ./build-env.sh

# Tool configuration
TOOL_NAME="example"
TOOL_DEPS=("dependency1" "dependency2")

# Verify dependencies
for dep in "${TOOL_DEPS[@]}"; do
  if [ ! -f "$PREFIX/$dep/.built" ]; then
    echo "ERROR: Dependency $dep not built"
    exit 1
  fi
done

# Download, configure, build, install
# ... build steps ...

# Create marker file
touch "$PREFIX/$TOOL_NAME/.built"
```

### Key Features

- **Dependency verification**: Checks that all dependencies are built before building
- **Logging**: All output logged to timestamped files in `logs/`
- **Artifact verification**: Verifies output files exist and are valid
- **Error handling**: Exits with non-zero status on failure
- **Environment isolation**: All configuration from build-env.sh

## Verification

### Verify Artifacts

```bash
# Verify built artifacts
./verify-artifacts.sh libnl3 libpcap iw
```

Checks:
- Output directories exist
- Libraries are valid ELF binaries
- Headers are readable
- Executables are for correct architecture

### Verify Tool Scripts

```bash
# Verify tool scripts follow conventions
./verify-tool-scripts.sh
```

Checks:
- Scripts source build-env.sh
- No hardcoded NDK paths
- Uses environment variables for toolchain

## Output Structure

Each tool installs to: `out/aarch64-linux-android/{tool_name}/`

```
out/aarch64-linux-android/libnl3/
├── lib/
│   ├── libnl-3.a
│   ├── libnl-3.so
│   ├── libnl-genl-3.a
│   └── libnl-genl-3.so
├── include/
│   └── libnl3/
│       ├── netlink/
│       └── netlink/genl/
├── bin/
└── .built (marker file)
```

## Extensibility

Adding a new tool is simple:

1. **Add source** to `src/TOOL/` directory (or let it download)
2. **Create** `scripts/build-{tool}.sh` following the template:
   ```bash
   #!/bin/bash
   set -euo pipefail
   source "$(dirname "${BASH_SOURCE[0]}")/build-env.sh"
   
   TOOL_NAME="mytool"
   TOOL_VERSION="1.0"
   TOOL_DEPS=("dependency1")
   
   # Check for local source first
   if [ -d "$SCRIPT_DIR/../src/mytool" ] && [ ! -d "$SRC_DIR/mytool-src" ]; then
     log "Using local source..."
     cp -r "$SCRIPT_DIR/../src/mytool" "$SRC_DIR/mytool-src"
   elif [ ! -d "$SRC_DIR/mytool-src" ]; then
     # Download logic here
   fi
   
   # Build, install, create .built marker
   ```
3. **Add entry** to `tools.conf`:
   ```
   mytool|1.0|dependency1|--enable-static|mytool.patch|autotools|no
   ```
4. **Run** `./builder build mytool`

The main build script automatically discovers and integrates new tools.

## Troubleshooting

### NDK Not Found

```bash
export ANDROID_NDK_HOME=/path/to/android-ndk
./builder build
```

### Build Fails

Check the log file:
```bash
tail -f logs/build-{tool}-*.log
```

### Dependency Issues

Verify dependency order:
```bash
./builder list
```

Rebuild dependencies:
```bash
./builder rebuild libnl3
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| ANDROID_NDK_HOME | (required) | Path to Android NDK |
| TARGET_TRIPLE | aarch64-linux-android | Target architecture triple |
| API_LEVEL | 29 | Android API level |
| PARALLEL_JOBS | $(nproc) | Number of parallel build jobs |
| VERBOSE | 0 | Enable verbose output (0 or 1) |
| KEEP_SOURCES | 1 | Keep downloaded sources after build |
| KEEP_BUILD_DIRS | 0 | Keep build directories after build |
| LOG_DIR | logs | Directory for build logs |

## Build Logs

All build output is logged to `logs/build-{tool}-{timestamp}.log`

View recent logs:
```bash
ls -lt logs/ | head -10
tail -f logs/build-libnl3-*.log
```

## Supported Tools

### Core Libraries

| Tool | Version | Dependencies | Type |
|------|---------|--------------|------|
| libnl3 | 3.7.0 | - | autotools |
| libpcap | 1.10.1 | - | autotools |
| libcap | 2.66 | - | autotools |
| libnet | 1.2.0 | - | autotools |
| openssl | 3.x | - | make |
| ifaddrs | master | - | make |
| radiotap | master | - | make |

### Wireless Security Tools

| Tool | Version | Dependencies | Type | Description |
|------|---------|--------------|------|-------------|
| aircrack-ng | 1.7 | libnet, libpcap, openssl | autotools | WiFi security suite (9 tools) |
| reaver | 1.6.6 | libpcap, libnl3 | autotools | WPS PIN cracking + wash scanner |
| mdk4 | master | libpcap, libnl3 | make | WiFi testing and attack tool |
| hcxdumptool | 6.2.7 | libpcap, openssl, ifaddrs | make | WiFi packet capture for hashcat |
| hcxtools | 6.2.7 | libpcap, openssl | make | Hash conversion tools (6 tools) |
| pixiewps | 1.4.2 | - | autotools | WPS Pixie Dust attack |
| macchanger | 1.7.0 | - | autotools | MAC address spoofing |
| iw | 5.16 | libnl3 | make | Wireless configuration utility |

### Network Tools

| Tool | Version | Dependencies | Type | Description |
|------|---------|--------------|------|-------------|
| nmap | 7.93 | - | autotools | Network scanner + ncat + nping |
| tcpdump | 4.99.1 | libpcap | autotools | Network packet analyzer |
| curl | 8.0.0 | - | autotools | URL transfer tool |

### Utilities

| Tool | Version | Dependencies | Type | Description |
|------|---------|--------------|------|-------------|
| busybox | 1.38.0 | - | make | Multi-call binary with Unix utilities |
| nano | 8.7 | - | autotools | Text editor |

**Total: 22 tools/libraries successfully building for Android ARM64 (aarch64), API 21+**

## Development

### Adding Patches

1. Place patch files in `patches/` directory
2. Reference in `tools.conf`:
   ```
   tool_name|version|deps|opts|patch-file.patch|type|is_library
   ```
3. Patches are applied after source preparation (local or downloaded)

### Customizing Flags

Edit architecture-specific config files:

```bash
# build-arm64.conf or build-arm.conf
TOOL_CFLAGS_mytool="-O3 -march=armv8-a"
TOOL_LDFLAGS_mytool="-Wl,-rpath,\$ORIGIN"
```

### Version Management

```bash
# Check for updates
./builder update

# Upgrade to latest version
./builder upgrade
```

The system pulls from the git repository and updates the version file.

## Files Excluded from Git

The `.gitignore` file excludes:
- Build artifacts (`build/`, `out/`, `logs/`)
- Downloaded tarballs (`*.tar.gz`, `*.tar.xz`, etc.)
- Object files and libraries (`*.o`, `*.a`, `*.so`)
- CMake and autotools artifacts
- Test directories
- Backup files

This keeps the repository clean and focused on source code and build scripts.

## Contributing

When contributing:
1. Place modified sources in `src/TOOL/` directory
2. Update build scripts to check local sources first
3. Document any new dependencies in `tools.conf`
4. Test on both ARM64 and ARM32 architectures
5. Update README.md with new features

## License

**Copyright (C) 2025, Christian <kimocoder> Bremvaag**

This build system is provided as-is for cross-compiling Android tools.

## References

- [Android NDK Documentation](https://developer.android.com/ndk)
- [libnl Documentation](https://www.infradead.org/~tgr/libnl/)
- [libpcap Documentation](https://www.tcpdump.org/papers/sniffing-faq.html)
- [Wireshark/tshark Documentation](https://www.wireshark.org/)
- [iw Documentation](https://wireless.wiki.kernel.org/en/users/documentation/iw)
- [busybox Documentation](https://busybox.net/)
- [nano Documentation](https://www.nano-editor.org/)
