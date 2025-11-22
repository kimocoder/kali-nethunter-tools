/*
 * Qualcomm Monitor Mode Test Tool
 * Standalone binary for testing monitor mode functionality via adb shell
 *
 * Usage:
 *   qcom_monitor_test <interface> <command> [options]
 *
 * Commands:
 *   enable              - Enable monitor mode
 *   disable             - Disable monitor mode
 *   status              - Get current monitor mode status
 *   enable-filter <hex> - Enable monitor mode with frame filtering
 *
 * Examples:
 *   qcom_monitor_test wlan0 enable
 *   qcom_monitor_test wlan0 status
 *   qcom_monitor_test wlan0 enable-filter 0x1F
 *   qcom_monitor_test wlan0 disable
 */

#include "qca_monitor.h"
#include <iostream>
#include <cstring>
#include <cstdlib>

// Color codes for output
#define COLOR_RESET   "\033[0m"
#define COLOR_RED     "\033[31m"
#define COLOR_GREEN   "\033[32m"
#define COLOR_YELLOW  "\033[33m"
#define COLOR_BLUE    "\033[34m"
#define COLOR_CYAN    "\033[36m"

void print_usage(const char* prog_name) {
    std::cout << "\n";
    std::cout << COLOR_CYAN << "Qualcomm Monitor Mode Test Tool" << COLOR_RESET << "\n";
    std::cout << "================================\n\n";
    std::cout << "Usage:\n";
    std::cout << "  " << prog_name << " <interface> <command> [options]\n\n";
    std::cout << "Commands:\n";
    std::cout << "  enable              - Enable monitor mode\n";
    std::cout << "  disable             - Disable monitor mode\n";
    std::cout << "  status              - Get current monitor mode status\n";
    std::cout << "  enable-filter <hex> - Enable monitor mode with frame filtering\n\n";
    std::cout << "Examples:\n";
    std::cout << "  " << prog_name << " wlan0 enable\n";
    std::cout << "  " << prog_name << " wlan0 status\n";
    std::cout << "  " << prog_name << " wlan0 enable-filter 0x1F\n";
    std::cout << "  " << prog_name << " wlan0 disable\n\n";
    std::cout << "Frame Type Flags (for enable-filter):\n";
    std::cout << "  0x01 - EAPOL frames (WPA handshakes)\n";
    std::cout << "  0x02 - ARP frames\n";
    std::cout << "  0x04 - DHCP frames\n";
    std::cout << "  0x08 - DNS frames\n";
    std::cout << "  0x10 - Management frames\n";
    std::cout << "  0x1F - All frame types\n\n";
}

const char* get_mode_name(int con_mode) {
    switch (con_mode) {
        case CON_MODE_MANAGED:
            return "Managed (STA)";
        case CON_MODE_SAP:
            return "Access Point";
        case CON_MODE_P2P:
            return "WiFi Direct";
        case CON_MODE_FTM:
            return "Factory Test Mode";
        case CON_MODE_MONITOR:
            return "Monitor";
        case CON_MODE_IBSS:
            return "Ad-hoc";
        default:
            return "Unknown";
    }
}

const char* get_error_name(int error_code) {
    switch (error_code) {
        case MONITOR_SUCCESS:
            return "Success";
        case MONITOR_ERROR_PERMISSION:
            return "Permission Denied";
        case MONITOR_ERROR_NOT_FOUND:
            return "Not Found";
        case MONITOR_ERROR_OPERATION_FAILED:
            return "Operation Failed";
        case MONITOR_ERROR_INTERFACE_DOWN:
            return "Interface Down Failed";
        case MONITOR_ERROR_INTERFACE_UP:
            return "Interface Up Failed";
        case MONITOR_ERROR_VERIFICATION_FAILED:
            return "Verification Failed";
        case MONITOR_ERROR_WIFI_CONFLICT:
            return "WiFi State Conflict";
        case MONITOR_ERROR_TIMEOUT:
            return "Timeout";
        default:
            return "Unknown Error";
    }
}

int cmd_enable(const std::string& interface) {
    std::cout << "\n" << COLOR_BLUE << "=== Enabling Monitor Mode ===" << COLOR_RESET << "\n\n";
    
    int result = QcomMonitorMode::enableMonitorMode(interface);
    
    std::cout << "\n";
    if (result == MONITOR_SUCCESS) {
        std::cout << COLOR_GREEN << "✓ Monitor mode enabled successfully!" << COLOR_RESET << "\n";
        return 0;
    } else {
        std::cout << COLOR_RED << "✗ Failed to enable monitor mode" << COLOR_RESET << "\n";
        std::cout << "  Error: " << get_error_name(result) << " (" << result << ")\n";
        return 1;
    }
}

int cmd_disable(const std::string& interface) {
    std::cout << "\n" << COLOR_BLUE << "=== Disabling Monitor Mode ===" << COLOR_RESET << "\n\n";
    
    int result = QcomMonitorMode::disableMonitorMode(interface);
    
    std::cout << "\n";
    if (result == MONITOR_SUCCESS) {
        std::cout << COLOR_GREEN << "✓ Monitor mode disabled successfully!" << COLOR_RESET << "\n";
        return 0;
    } else {
        std::cout << COLOR_RED << "✗ Failed to disable monitor mode" << COLOR_RESET << "\n";
        std::cout << "  Error: " << get_error_name(result) << " (" << result << ")\n";
        return 1;
    }
}

int cmd_status(const std::string& interface) {
    std::cout << "\n" << COLOR_BLUE << "=== Monitor Mode Status ===" << COLOR_RESET << "\n\n";
    
    int con_mode = QcomMonitorMode::getMonitorModeStatus(interface);
    
    if (con_mode < 0) {
        std::cout << COLOR_RED << "✗ Failed to get status" << COLOR_RESET << "\n";
        std::cout << "  Error: " << get_error_name(con_mode) << " (" << con_mode << ")\n";
        return 1;
    }
    
    std::cout << "Interface: " << interface << "\n";
    std::cout << "con_mode:  " << con_mode << " (" << get_mode_name(con_mode) << ")\n";
    
    if (con_mode == CON_MODE_MONITOR) {
        std::cout << COLOR_GREEN << "Status:    Monitor mode ENABLED" << COLOR_RESET << "\n";
    } else if (con_mode == CON_MODE_MANAGED) {
        std::cout << COLOR_YELLOW << "Status:    Managed mode (normal WiFi)" << COLOR_RESET << "\n";
    } else {
        std::cout << COLOR_YELLOW << "Status:    Other mode" << COLOR_RESET << "\n";
    }
    
    std::cout << "\n";
    return 0;
}

int cmd_enable_filter(const std::string& interface, uint32_t frame_types) {
    std::cout << "\n" << COLOR_BLUE << "=== Enabling Monitor Mode with Filtering ===" << COLOR_RESET << "\n\n";
    std::cout << "Frame types: 0x" << std::hex << frame_types << std::dec << "\n\n";
    
    int result = QcomMonitorMode::enableMonitorModeWithFiltering(interface, frame_types);
    
    std::cout << "\n";
    if (result == MONITOR_SUCCESS) {
        std::cout << COLOR_GREEN << "✓ Monitor mode with filtering enabled!" << COLOR_RESET << "\n";
        return 0;
    } else {
        std::cout << COLOR_RED << "✗ Failed to enable monitor mode with filtering" << COLOR_RESET << "\n";
        std::cout << "  Error: " << get_error_name(result) << " (" << result << ")\n";
        return 1;
    }
}

int main(int argc, char** argv) {
    // Check minimum arguments
    if (argc < 3) {
        print_usage(argv[0]);
        return 1;
    }
    
    std::string interface = argv[1];
    std::string command = argv[2];
    
    // Execute command
    if (command == "enable") {
        return cmd_enable(interface);
    } else if (command == "disable") {
        return cmd_disable(interface);
    } else if (command == "status") {
        return cmd_status(interface);
    } else if (command == "enable-filter") {
        if (argc < 4) {
            std::cerr << COLOR_RED << "Error: enable-filter requires frame type argument" << COLOR_RESET << "\n";
            print_usage(argv[0]);
            return 1;
        }
        
        // Parse frame types (hex or decimal)
        uint32_t frame_types;
        if (strncmp(argv[3], "0x", 2) == 0 || strncmp(argv[3], "0X", 2) == 0) {
            frame_types = strtoul(argv[3], nullptr, 16);
        } else {
            frame_types = strtoul(argv[3], nullptr, 10);
        }
        
        return cmd_enable_filter(interface, frame_types);
    } else {
        std::cerr << COLOR_RED << "Error: Unknown command '" << command << "'" << COLOR_RESET << "\n";
        print_usage(argv[0]);
        return 1;
    }
    
    return 0;
}
