#!/bin/bash

# Test script for Qualcomm Monitor Mode on real device via adb shell
# Comprehensive testing of monitor mode functionality

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

INTERFACE=${1:-wlan0}
TEST_BINARY="/data/local/tmp/qcom_monitor_test"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Qualcomm Monitor Mode Device Test${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "${BLUE}Interface: $INTERFACE${NC}"
echo ""

# Check if device is connected
echo -e "${BLUE}Checking device connection...${NC}"
if ! adb devices | grep -q "device$"; then
    echo -e "${RED}✗ No device connected${NC}"
    echo "Please connect a device and enable USB debugging"
    exit 1
fi
echo -e "${GREEN}✓ Device connected${NC}"
echo ""

# Check if binary exists locally
LOCAL_BINARY="netlink/tests/bin/qcom_monitor_test_arm64-v8a"
if [ ! -f "$LOCAL_BINARY" ]; then
    echo -e "${YELLOW}⚠ Test binary not found: $LOCAL_BINARY${NC}"
    echo "Building test binary..."
    ./netlink/tests/build_qcom_monitor_test.sh arm64-v8a
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Build failed${NC}"
        exit 1
    fi
fi

# Push binary to device
echo -e "${BLUE}Deploying test binary to device...${NC}"
adb push "$LOCAL_BINARY" "$TEST_BINARY" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Failed to push binary${NC}"
    exit 1
fi

adb shell chmod +x "$TEST_BINARY" > /dev/null 2>&1
echo -e "${GREEN}✓ Binary deployed${NC}"
echo ""

# Test 1: Check status (no root required)
echo -e "${CYAN}=== Test 1: Status Check (No Root) ===${NC}"
echo -e "${BLUE}Testing status query without root access...${NC}"
adb unroot > /dev/null 2>&1
sleep 1
adb shell "$TEST_BINARY $INTERFACE status"
echo ""

# Get root access
echo -e "${CYAN}=== Obtaining Root Access ===${NC}"
adb root > /dev/null 2>&1
sleep 2
if ! adb shell "id" | grep -q "uid=0"; then
    echo -e "${RED}✗ Failed to obtain root access${NC}"
    echo "Some tests will be skipped"
    HAS_ROOT=false
else
    echo -e "${GREEN}✓ Root access obtained${NC}"
    HAS_ROOT=true
fi
echo ""

if [ "$HAS_ROOT" = true ]; then
    # Test 2: Check current con_mode
    echo -e "${CYAN}=== Test 2: Check con_mode via sysfs ===${NC}"
    echo -e "${BLUE}Reading /sys/module/wlan/parameters/con_mode...${NC}"
    CON_MODE=$(adb shell "cat /sys/module/wlan/parameters/con_mode 2>&1" | tr -d '\r')
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ con_mode: $CON_MODE${NC}"
        case $CON_MODE in
            0) echo "  Mode: Managed (STA)" ;;
            4) echo "  Mode: Monitor" ;;
            *) echo "  Mode: Other ($CON_MODE)" ;;
        esac
    else
        echo -e "${RED}✗ Failed to read con_mode${NC}"
    fi
    echo ""
    
    # Test 3: Enable monitor mode
    echo -e "${CYAN}=== Test 3: Enable Monitor Mode ===${NC}"
    adb shell "$TEST_BINARY $INTERFACE enable"
    RESULT=$?
    echo ""
    
    if [ $RESULT -eq 0 ]; then
        # Test 4: Verify con_mode changed
        echo -e "${CYAN}=== Test 4: Verify con_mode Changed ===${NC}"
        echo -e "${BLUE}Checking con_mode after enable...${NC}"
        NEW_CON_MODE=$(adb shell "cat /sys/module/wlan/parameters/con_mode 2>&1" | tr -d '\r')
        if [ "$NEW_CON_MODE" = "4" ]; then
            echo -e "${GREEN}✓ con_mode is 4 (monitor mode)${NC}"
        else
            echo -e "${RED}✗ con_mode is $NEW_CON_MODE (expected 4)${NC}"
        fi
        echo ""
        
        # Test 5: Verify interface type
        echo -e "${CYAN}=== Test 5: Verify Interface Type ===${NC}"
        echo -e "${BLUE}Checking interface type via iw...${NC}"
        IW_OUTPUT=$(adb shell "iw dev $INTERFACE info 2>&1" | grep "type")
        echo "$IW_OUTPUT"
        if echo "$IW_OUTPUT" | grep -q "monitor"; then
            echo -e "${GREEN}✓ Interface type is monitor${NC}"
        else
            echo -e "${YELLOW}⚠ Interface type not confirmed as monitor${NC}"
        fi
        echo ""
        
        # Test 6: Check kernel logs
        echo -e "${CYAN}=== Test 6: Check Kernel Logs ===${NC}"
        echo -e "${BLUE}Searching for monitor mode messages...${NC}"
        KERNEL_LOGS=$(adb shell "dmesg | tail -50 | grep -i 'monitor mode'" | tail -5)
        if [ -n "$KERNEL_LOGS" ]; then
            echo -e "${GREEN}✓ Monitor mode messages found:${NC}"
            echo "$KERNEL_LOGS"
        else
            echo -e "${YELLOW}⚠ No monitor mode messages in recent logs${NC}"
        fi
        echo ""
        
        # Test 7: Disable monitor mode
        echo -e "${CYAN}=== Test 7: Disable Monitor Mode ===${NC}"
        adb shell "$TEST_BINARY $INTERFACE disable"
        RESULT=$?
        echo ""
        
        if [ $RESULT -eq 0 ]; then
            # Test 8: Verify con_mode reset
            echo -e "${CYAN}=== Test 8: Verify con_mode Reset ===${NC}"
            echo -e "${BLUE}Checking con_mode after disable...${NC}"
            FINAL_CON_MODE=$(adb shell "cat /sys/module/wlan/parameters/con_mode 2>&1" | tr -d '\r')
            if [ "$FINAL_CON_MODE" = "0" ]; then
                echo -e "${GREEN}✓ con_mode is 0 (managed mode)${NC}"
            else
                echo -e "${RED}✗ con_mode is $FINAL_CON_MODE (expected 0)${NC}"
            fi
            echo ""
        fi
    fi
    
    # Test 9: Test with invalid interface
    echo -e "${CYAN}=== Test 9: Error Handling (Invalid Interface) ===${NC}"
    echo -e "${BLUE}Testing with invalid interface 'wlan999'...${NC}"
    adb shell "$TEST_BINARY wlan999 status" 2>&1 | tail -5
    echo ""
    
fi

# Summary
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Test Summary${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
if [ "$HAS_ROOT" = true ]; then
    echo -e "${GREEN}✓ All tests completed${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Review test output above"
    echo "  2. Verify monitor mode worked correctly"
    echo "  3. Check for any errors or warnings"
    echo "  4. Proceed with JNI integration if tests pass"
else
    echo -e "${YELLOW}⚠ Limited testing (no root access)${NC}"
    echo ""
    echo "To run full tests:"
    echo "  1. Enable root access on device"
    echo "  2. Run: adb root"
    echo "  3. Re-run this script"
fi
echo ""
