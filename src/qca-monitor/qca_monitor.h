#ifndef QCOM_MONITOR_MODE_H
#define QCOM_MONITOR_MODE_H

#include <string>
#include <cstdint>

// Qualcomm con_mode values
// These control the interface mode via /sys/module/wlan/parameters/con_mode
enum ConMode {
    CON_MODE_MANAGED = 0,      // STA mode (normal WiFi)
    CON_MODE_SAP = 1,          // Access Point mode
    CON_MODE_P2P = 2,          // WiFi Direct
    CON_MODE_FTM = 3,          // Factory Test Mode
    CON_MODE_MONITOR = 4,      // Monitor mode
    CON_MODE_IBSS = 5          // Ad-hoc mode
};

// Qualcomm device mode values
// These are the driver's internal representation of interface type
enum DeviceMode {
    DEVICE_MODE_MANAGED = 0,   // Managed/STA mode
    DEVICE_MODE_MONITOR = 6    // Monitor mode
};

// Return codes for monitor mode operations
enum MonitorModeResult {
    MONITOR_SUCCESS = 0,
    MONITOR_ERROR_PERMISSION = -1,
    MONITOR_ERROR_NOT_FOUND = -2,
    MONITOR_ERROR_OPERATION_FAILED = -3,
    MONITOR_ERROR_INTERFACE_DOWN = -4,
    MONITOR_ERROR_INTERFACE_UP = -5,
    MONITOR_ERROR_VERIFICATION_FAILED = -6,
    MONITOR_ERROR_WIFI_CONFLICT = -7,
    MONITOR_ERROR_TIMEOUT = -8
};

// Monitor mode status information
struct MonitorModeStatus {
    int con_mode;              // Current con_mode value (0, 4, etc.)
    int device_mode;           // Driver device mode (0=managed, 6=monitor)
    bool interface_up;         // Interface state
    bool monitor_confirmed;    // Verified via kernel logs
    std::string error_message; // Error details if any
};

// Monitor mode configuration
struct MonitorModeConfig {
    std::string interface;     // Interface name (e.g., "wlan0")
    int target_mode;           // Target con_mode (0 or 4)
    bool enable_filtering;     // Enable frame filtering
    uint32_t frame_types;      // Frame types to capture (if filtering enabled)
    int timeout_ms;            // Timeout for operations
};


// QcomMonitorMode class - Core implementation for Qualcomm monitor mode management
class QcomMonitorMode {
public:
    // Enable monitor mode on specified interface
    // Returns: MONITOR_SUCCESS on success, error code on failure
    static int enableMonitorMode(const std::string& interface);
    
    // Disable monitor mode (return to managed mode)
    // Returns: MONITOR_SUCCESS on success, error code on failure
    static int disableMonitorMode(const std::string& interface);
    
    // Get current monitor mode status
    // Returns: con_mode value (0, 4, etc.) or error code on failure
    static int getMonitorModeStatus(const std::string& interface);
    
    // Enable monitor mode with frame filtering
    // Returns: MONITOR_SUCCESS on success, error code on failure
    static int enableMonitorModeWithFiltering(
        const std::string& interface,
        uint32_t frameTypes
    );
    
    // Get detailed status information
    // Returns: MonitorModeStatus struct with current state
    static MonitorModeStatus getDetailedStatus(const std::string& interface);

private:
    // Set con_mode parameter via sysfs
    // mode: Target con_mode value (0=managed, 4=monitor)
    // Returns: MONITOR_SUCCESS on success, error code on failure
    static int setConMode(int mode);
    
    // Get current con_mode value from sysfs
    // Returns: con_mode value or error code on failure
    static int getConMode();
    
    // Bring interface down
    // interface: Interface name (e.g., "wlan0")
    // Returns: MONITOR_SUCCESS on success, error code on failure
    static int interfaceDown(const std::string& interface);
    
    // Bring interface up
    // interface: Interface name (e.g., "wlan0")
    // Returns: MONITOR_SUCCESS on success, error code on failure
    static int interfaceUp(const std::string& interface);
    
    // Verify monitor mode is active
    // interface: Interface name to verify
    // Returns: true if monitor mode confirmed, false otherwise
    static bool verifyMonitorMode(const std::string& interface);
    
    // Check for WiFi state conflicts
    // Returns: true if conflict detected, false otherwise
    static bool checkWiFiStateConflict();
    
    // Get device mode from driver
    // interface: Interface name
    // Returns: device_mode value or error code on failure
    static int getDeviceMode(const std::string& interface);
    
    // Check kernel logs for monitor mode confirmation
    // Returns: true if "Monitor mode is enabled" found in logs
    static bool checkKernelLogs();
    
    // Stop wpa_supplicant process
    // interface: Interface name (for logging purposes)
    // Returns: MONITOR_SUCCESS on success, error code on failure
    static int stopWpaSupplicant(const std::string& interface);
    
    // Start wpa_supplicant process
    // interface: Interface name (for logging purposes)
    // Returns: MONITOR_SUCCESS on success, error code on failure
    static int startWpaSupplicant(const std::string& interface);
    
    // Check if wpa_supplicant is running
    // Returns: true if running, false otherwise
    static bool isWpaSupplicantRunning();
};

#endif // QCOM_MONITOR_MODE_H
