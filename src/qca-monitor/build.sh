#!/bin/bash

# Build script for Qualcomm Monitor Mode Test Tool
# Builds standalone binary for adb shell testing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Qualcomm Monitor Mode Test Tool Builder${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check for Android NDK
if [ -z "$ANDROID_NDK" ]; then
    echo -e "${RED}Error: ANDROID_NDK environment variable not set${NC}"
    echo "Please set it to your NDK path, e.g.:"
    echo "  export ANDROID_NDK=/path/to/android-ndk"
    exit 1
fi

if [ ! -d "$ANDROID_NDK" ]; then
    echo -e "${RED}Error: ANDROID_NDK path does not exist: $ANDROID_NDK${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Android NDK found: $ANDROID_NDK${NC}"

# Determine architecture (default to arm64-v8a)
ABI=${1:-arm64-v8a}
echo -e "${BLUE}Building for architecture: $ABI${NC}"

# Set up toolchain
case $ABI in
    arm64-v8a)
        TOOLCHAIN="aarch64-linux-android"
        API_LEVEL=21
        ;;
    armeabi-v7a)
        TOOLCHAIN="armv7a-linux-androideabi"
        API_LEVEL=21
        ;;
    x86_64)
        TOOLCHAIN="x86_64-linux-android"
        API_LEVEL=21
        ;;
    x86)
        TOOLCHAIN="i686-linux-android"
        API_LEVEL=21
        ;;
    *)
        echo -e "${RED}Error: Unsupported architecture: $ABI${NC}"
        echo "Supported: arm64-v8a, armeabi-v7a, x86_64, x86"
        exit 1
        ;;
esac

# Set up compiler
TOOLCHAIN_DIR="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64"
if [ ! -d "$TOOLCHAIN_DIR" ]; then
    # Try macOS path
    TOOLCHAIN_DIR="$ANDROID_NDK/toolchains/llvm/prebuilt/darwin-x86_64"
fi

if [ ! -d "$TOOLCHAIN_DIR" ]; then
    echo -e "${RED}Error: Could not find NDK toolchain${NC}"
    exit 1
fi

CXX="$TOOLCHAIN_DIR/bin/${TOOLCHAIN}${API_LEVEL}-clang++"
if [ ! -f "$CXX" ]; then
    echo -e "${RED}Error: Compiler not found: $CXX${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Compiler found: $CXX${NC}"

# Create output directory
OUTPUT_DIR="netlink/tests/bin"
mkdir -p "$OUTPUT_DIR"

# Source files
SOURCES=(
    "netlink/tests/qcom_monitor_test.cpp"
    "netlink/qcom_monitor_mode.cpp"
    "netlink/tests/vendor_cmd_stub.cpp"
)

# Check source files exist
echo -e "${BLUE}Checking source files...${NC}"
for src in "${SOURCES[@]}"; do
    if [ ! -f "$src" ]; then
        echo -e "${RED}Error: Source file not found: $src${NC}"
        exit 1
    fi
    echo -e "${GREEN}  ✓ $src${NC}"
done

# Compile
echo -e "${BLUE}Compiling...${NC}"
OUTPUT_BIN="$OUTPUT_DIR/qcom_monitor_test_${ABI}"

$CXX \
    -std=c++11 \
    -O2 \
    -fPIE \
    -pie \
    -I netlink \
    -I netlink/libnl/include \
    -D__ANDROID__ \
    -DANDROID \
    "${SOURCES[@]}" \
    -o "$OUTPUT_BIN" \
    -llog \
    -static-libstdc++

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Build successful!${NC}"
    echo ""
    echo -e "${BLUE}Output:${NC} $OUTPUT_BIN"
    echo -e "${BLUE}Size:${NC}   $(du -h "$OUTPUT_BIN" | cut -f1)"
    echo ""
    echo -e "${YELLOW}To test on device:${NC}"
    echo "  adb root"
    echo "  adb push $OUTPUT_BIN /data/local/tmp/qcom_monitor_test"
    echo "  adb shell chmod +x /data/local/tmp/qcom_monitor_test"
    echo "  adb shell /data/local/tmp/qcom_monitor_test wlan0 status"
    echo ""
else
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi
