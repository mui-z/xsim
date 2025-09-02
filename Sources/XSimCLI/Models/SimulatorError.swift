import Foundation

/// Custom error types for simulator operations
public enum SimulatorError: Error, LocalizedError, Equatable {
    /// Device with the specified identifier was not found
    case deviceNotFound(String)

    /// Device is already running
    case deviceAlreadyRunning(String)

    /// Device is not currently running
    case deviceNotRunning(String)

    /// Invalid device type specified
    case invalidDeviceType(String)

    /// Invalid runtime specified
    case invalidRuntime(String)

    /// App bundle was not found at the specified path
    case appBundleNotFound(String)

    /// simctl command execution failed
    case simctlCommandFailed(String)

    /// Insufficient permissions to perform the operation
    case insufficientPermissions

    /// No devices are available
    case noDevicesAvailable

    /// Invalid device identifier format
    case invalidDeviceIdentifier(String)

    /// Operation timed out
    case operationTimeout

    /// Xcode command line tools are not installed
    case xcodeToolsNotInstalled

    public var errorDescription: String? {
        switch self {
        case let .deviceNotFound(identifier):
            "Device '\(identifier)' was not found. Run 'xsim list' to see available devices."

        case let .deviceAlreadyRunning(identifier):
            "Device '\(identifier)' is already running."

        case let .deviceNotRunning(identifier):
            "Device '\(identifier)' is not running."

        case let .invalidDeviceType(deviceType):
            "Invalid device type '\(deviceType)'. Run 'xsim create --list-types' to list device types."

        case let .invalidRuntime(runtime):
            "Invalid runtime '\(runtime)'. Run 'xsim create --list-runtimes' to list runtimes."

        case let .appBundleNotFound(path):
            "No app bundle found at path '\(path)'. Please verify the path."

        case let .simctlCommandFailed(message):
            "Failed to execute simctl: \(message)"

        case .insufficientPermissions:
            "Insufficient permissions to perform the operation. Try running with administrator privileges."

        case .noDevicesAvailable:
            "No devices available. Use 'xsim create' to create a new simulator."

        case let .invalidDeviceIdentifier(identifier):
            "Invalid device identifier '\(identifier)'. Specify a device name or UUID."

        case .operationTimeout:
            "Operation timed out. Please wait a moment and try again."

        case .xcodeToolsNotInstalled:
            "Xcode Command Line Tools are not installed. Run 'xcode-select --install' to install them."
        }
    }

    public var failureReason: String? {
        switch self {
        case .deviceNotFound:
            "The specified device does not exist"
        case .deviceAlreadyRunning:
            "The device is already running"
        case .deviceNotRunning:
            "The device is currently stopped"
        case .invalidDeviceType:
            "Unsupported device type"
        case .invalidRuntime:
            "Unsupported runtime"
        case .appBundleNotFound:
            "App bundle not found"
        case .simctlCommandFailed:
            "simctl execution error"
        case .insufficientPermissions:
            "Insufficient permissions"
        case .noDevicesAvailable:
            "No devices available"
        case .invalidDeviceIdentifier:
            "Invalid device identifier"
        case .operationTimeout:
            "Operation timed out"
        case .xcodeToolsNotInstalled:
            "Xcode Command Line Tools not installed"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .deviceNotFound:
            "Run 'xsim list' to see available devices"
        case .deviceAlreadyRunning:
            "The device is already running; no action is needed"
        case .deviceNotRunning:
            "Boot the device with 'xsim boot <device>'"
        case .invalidDeviceType:
            "Run 'xsim create --list-types' to list available device types"
        case .invalidRuntime:
            "Run 'xsim create --list-runtimes' to list available runtimes"
        case .appBundleNotFound:
            "Verify the app bundle path is correct"
        case .simctlCommandFailed:
            "Verify that Xcode is properly installed"
        case .insufficientPermissions:
            "Run with administrator privileges, or check file permissions"
        case .noDevicesAvailable:
            "Create a new simulator with 'xsim create'"
        case .invalidDeviceIdentifier:
            "Specify a valid device name or UUID"
        case .operationTimeout:
            "Wait a moment and try again"
        case .xcodeToolsNotInstalled:
            "Run 'xcode-select --install' to install the Xcode Command Line Tools"
        }
    }
}
