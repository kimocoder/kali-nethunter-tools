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

- **build.sh**: Main orchestration script with dependency management, multi-arch support, and comprehensive cleaning
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
./build.sh list

# Build all tools for both architectures
./build.sh build

# Build for specific architecture
./build.sh build --arch arm64    # 64-bit only
./build.sh build --arch arm      # 32-bit only

# Build specific tools (dependencies auto-built)
./build.sh build iw tcpdump

# Check build status
./build.sh status

# Clean all build artifacts
./build.sh clean

# Push to Android device
./build.sh push iw tcpdump
```

## Architecture

### Directory Structure

```
.
├── build.sh                   # Main orchestrator
├── build-env.sh              # Environment configuration (in scripts/)
├── scripts/                  # Tool-specific build scripts
│   ├── build-env.sh          # Environment configuration
│   ├── build-libnl3.sh
│   ├── build-libpcap.sh
│   ├── build-openssl.sh
│   ├── build-aircrack-ng.sh
│   ├── build-reaver.sh
│   ├── build-mdk4.sh
│   ├── verify-artifacts.sh   # Artifact verification
│   ├── verify-tool-scripts.sh # Tool script validation
│   ├── fix-tls-alignment.py  # TLS alignment fix for ARM64
│   └── ... (all tool scripts)
├── tools.conf                # Tool manifest
├── build.conf                # Build configuration
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
  libnl3, libpcap, libcap, libnet, libmnl, openssl, ifaddrs, radiotap
  zlib, c-ares, libffi, pcre2, libintl-lite, libxml2, libgpg-error, libgcrypt, glib2

Wireless Tools:
  libnl3 ──────┬─→ mdk4 (also needs libpcap)
               └─→ aircrack-ng (also needs libpcap, libnet, openssl)
  
  libpcap ─────┬─→ tcpdump
               ├─→ tshark (also needs glib2, zlib, c-ares, libgcrypt, pcre2, libxml2, libintl-lite, libnl3)
               ├─→ aircrack-ng (also needs libnet, openssl, libnl3)
               ├─→ reaver (also needs libnl3)
               ├─→ hcxdumptool (also needs openssl, ifaddrs)
               └─→ hcxtools (also needs openssl)
  
  openssl ─────┬─→ aircrack-ng
               ├─→ hcxdumptool
               └─→ hcxtools

Network Tools:
  libnl3 ──────→ iw
  libmnl ──────┬─→ iproute2
               └─→ ethtool
  nmap, rfkill, net-tools (no dependencies)

Utilities:
  busybox, nano, strace, curl, pixiewps, macchanger, qca-monitor, wireless-tools (no dependencies)
```

## Usage

### Build Commands

```bash
# Build all tools in dependency order
./build.sh build

# Build specific tools (with dependencies)
./build.sh build iw libpcap

# Build for specific architecture
./build.sh build --arch arm64           # 64-bit ARM only
./build.sh build --arch arm             # 32-bit ARM only
./build.sh build --arch both            # Both architectures (default)

# Clean all artifacts (removes build dirs, tarballs, .o files)
./build.sh clean

# Clean specific tool
./build.sh clean iw

# Rebuild (clean + build)
./build.sh rebuild

# List available tools
./build.sh list

# Show build status
./build.sh status

# Check for updates
./build.sh update

# Upgrade to latest version
./build.sh upgrade

# Push tools to Android device via ADB
./build.sh push iw tcpdump

# Show help
./build.sh help
```

### Verbose Output

```bash
# Enable verbose logging
VERBOSE=1 ./build.sh build

# Or use flag
./build.sh -v build
```

### Parallel Jobs

```bash
# Control number of parallel build jobs
PARALLEL_JOBS=4 ./build.sh build
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
./build.sh build curl

# Copy to local source directory
cp -r scripts/build/curl/src/curl-src src/curl

# Clean and rebuild (now uses local source)
./build.sh clean curl
./build.sh build curl  # Uses src/curl
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
./scripts/verify-artifacts.sh libnl3 libpcap iw
```

Checks:
- Output directories exist
- Libraries are valid ELF binaries
- Headers are readable
- Executables are for correct architecture

### Verify Tool Scripts

```bash
# Verify tool scripts follow conventions
./scripts/verify-tool-scripts.sh
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
4. **Run** `./build.sh build mytool`

The main build script automatically discovers and integrates new tools.

## ARM64 TLS Alignment

Android Bionic on ARM64 requires TLS (Thread-Local Storage) segments to be aligned to 64 bytes. Some tools built with older toolchains may have 8-byte alignment, causing this error:

```
error: executable's TLS segment is underaligned: alignment is 8, needs to be at least 64
```

The build system automatically fixes this for ARM64 binaries using `scripts/fix-tls-alignment.py`, which patches the ELF headers to set proper alignment. This is applied automatically during the build process for affected tools like:
- iproute2 (ip, tc, ss, etc.)
- net-tools (ifconfig, netstat, route, arp, etc.)
- ethtool
- wireless-tools (iwconfig, iwlist, iwspy, etc.)

No manual intervention is required - the fix is integrated into the build scripts.

## Troubleshooting

### NDK Not Found

```bash
export ANDROID_NDK_HOME=/path/to/android-ndk
./build.sh build
```

### Build Fails

Check the log file:
```bash
tail -f logs/build-{tool}-*.log
```

### Dependency Issues

Verify dependency order:
```bash
./build.sh list
```

Rebuild dependencies:
```bash
./build.sh rebuild libnl3
```

### TLS Alignment Errors on ARM64

If you see TLS alignment errors, the automatic fix may have failed. Manually apply it:

```bash
python3 scripts/fix-tls-alignment.py path/to/binary
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
| libmnl | 1.0.5 | - | autotools |
| openssl | 3.x | - | make |
| ifaddrs | master | - | make |
| radiotap | master | - | make |

### Wireless Security Tools

| Tool | Version | Dependencies | Type | Description |
|------|---------|--------------|------|-------------|
| aircrack-ng | 1.7 | libnet, libpcap, openssl | autotools | WiFi security suite (9 tools) |
| reaver | 1.6.6 | libpcap, libnl3 | autotools | WPS PIN cracking + wash scanner |
| mdk4 | master | libpcap, libnl3 | make | WiFi testing and attack tool |
| hcxdumptool | 7.0.1 | libpcap, openssl, ifaddrs | make | WiFi packet capture for hashcat |
| hcxtools | 7.0.1 | libpcap, openssl | make | Hash conversion tools (6 tools) |
| pixiewps | 1.4.2 | - | autotools | WPS Pixie Dust attack |
| macchanger | 1.7.0 | - | autotools | MAC address spoofing |
| wireless-tools | 30.pre9 | - | make | Classic wireless tools (iwconfig, iwlist, iwspy, etc.) |
| qca-monitor | master | - | make | Qualcomm monitor mode enabler |

### Network Tools

| Tool | Version | Dependencies | Type | Description |
|------|---------|--------------|------|-------------|
| nmap | 7.93 | - | autotools | Network scanner + ncat + nping |
| tcpdump | 4.99.1 | libpcap | autotools | Network packet analyzer |
| tshark | 4.0.0 | libpcap, glib2, zlib, c-ares, libgcrypt, pcre2, libxml2, libintl-lite, libnl3 | cmake | Wireshark terminal-based packet analyzer |
| iw | 5.16 | libnl3 | make | Wireless configuration utility |
| rfkill | 1.0 | - | make | Tool to enable/disable wireless devices |
| iproute2 | 6.1.0 | libmnl | make | Advanced routing and network configuration (ip, tc, ss, etc.) |
| net-tools | 2.10 | - | make | Classic network tools (ifconfig, netstat, route, arp, etc.) |
| ethtool | 6.15 | libmnl | autotools | Ethernet interface configuration and tuning |

### Utilities

| Tool | Version | Dependencies | Type | Description |
|------|---------|--------------|------|-------------|
| busybox | 1.38.0 | - | make | Multi-call binary with Unix utilities |
| nano | 8.7 | ncurses | autotools | Text editor |
| strace | 6.12 | - | autotools | System call tracer for debugging |
| curl | 8.0.0 | - | autotools | URL transfer tool |

**Total: 30 tools/libraries successfully building for Android ARM64 (aarch64), API 21+**

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
./build.sh update

# Upgrade to latest version
./build.sh upgrade
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
