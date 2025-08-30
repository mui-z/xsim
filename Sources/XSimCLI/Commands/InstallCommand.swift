import Foundation
import Rainbow
import SwiftCLI

/// Command to install an app on a simulator device
class InstallCommand: BaseSimCommand, Command {
    let name = "install"
    let shortDescription = "Install an app to a simulator"
    let longDescription = """
    Installs an application to the specified simulator device.
    Provide the .app bundle path, and specify the target device by name or UUID.
    If the device is stopped, it will be started automatically.

    Examples:
      xsim install "iPhone 15" /path/to/MyApp.app
      xsim install 12345678-1234-1234-1234-123456789012 ~/Desktop/MyApp.app
    """

    @Param var deviceIdentifier: String
    @Param var appBundlePath: String

    override init() {}

    func execute() throws {
        do {
            // Expand tilde in path
            let expandedPath = expandPath(appBundlePath)

            // Validate app bundle path first
            try validateAppBundle(at: expandedPath)

            // Get device info
            let simulatorService = try getService()
            let devices = try simulatorService.listDevices()
            guard let device = findDevice(in: devices, identifier: deviceIdentifier) else {
                throw SimulatorError.deviceNotFound(deviceIdentifier)
            }

            // Check if device needs to be started
            if !device.state.isRunning {
                stdout <<< "Device is stopped. Starting it...".dim
                try simulatorService.startSimulator(identifier: deviceIdentifier)
                stdout <<< "✓ Started the device".green
                stdout <<< ""
            }

            // Get app info
            let appInfo = try extractAppInfo(from: expandedPath)

            stdout <<< "Installing the app...".dim

            // Install the app
            try simulatorService.installApp(bundlePath: expandedPath, deviceIdentifier: deviceIdentifier)

            displayInstallSuccess(device: device, appInfo: appInfo, appPath: expandedPath)

        } catch let error as SimulatorError {
            try handleSimulatorError(error)
        } catch {
            throw CLI.Error(message: "An unexpected error occurred: \(error.localizedDescription)")
        }
    }

    /// Expands tilde (~) in file paths
    private func expandPath(_ path: String) -> String {
        if path.hasPrefix("~") {
            return NSString(string: path).expandingTildeInPath
        }
        return path
    }

    /// Validates that the app bundle exists and is valid
    private func validateAppBundle(at path: String) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        // Check if path exists
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw SimulatorError.appBundleNotFound(path)
        }

        // Check if it's a directory
        guard isDirectory.boolValue else {
            throw SimulatorError.appBundleNotFound(path)
        }

        // Check if it has .app extension
        guard path.hasSuffix(".app") else {
            throw SimulatorError.appBundleNotFound(path)
        }

        // Check if Info.plist exists
        let infoPlistPath = (path as NSString).appendingPathComponent("Info.plist")
        guard fileManager.fileExists(atPath: infoPlistPath) else {
            throw SimulatorError.appBundleNotFound(path)
        }
    }

    /// Extracts app information from the bundle
    private func extractAppInfo(from bundlePath: String) throws -> AppInfo {
        let infoPlistPath = (bundlePath as NSString).appendingPathComponent("Info.plist")

        guard let plistData = FileManager.default.contents(atPath: infoPlistPath),
              let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        else {
            return AppInfo(name: (bundlePath as NSString).lastPathComponent, bundleIdentifier: nil, version: nil)
        }

        let appName = plist["CFBundleDisplayName"] as? String ??
            plist["CFBundleName"] as? String ??
            (bundlePath as NSString).lastPathComponent

        let bundleIdentifier = plist["CFBundleIdentifier"] as? String
        let version = plist["CFBundleShortVersionString"] as? String

        return AppInfo(name: appName, bundleIdentifier: bundleIdentifier, version: version)
    }

    /// Handles specific simulator errors with helpful messages
    private func handleSimulatorError(_ error: SimulatorError) throws {
        switch error {
        case let .deviceNotFound(identifier):
            stdout <<< "✗ Device '\(identifier)' not found".red
            stdout <<< ""
            stdout <<< "To list available devices:".dim
            stdout <<< "  xsim list".cyan
            throw CLI.Error(message: "")

        case let .appBundleNotFound(path):
            stdout <<< "✗ App bundle not found: \(path)".red
            stdout <<< ""
            stdout <<< "Please check:".dim
            stdout <<< "  • The path is correct"
            stdout <<< "  • The file has a .app extension"
            stdout <<< "  • The bundle contains an Info.plist file"
            throw CLI.Error(message: "")

        case let .deviceNotRunning(identifier):
            stdout <<< "✗ Device '\(identifier)' is not running".red
            stdout <<< ""
            stdout <<< "Start the device, then retry:".dim
            stdout <<< "  xsim start \"\(identifier)\"".cyan
            throw CLI.Error(message: "")

        default:
            throw CLI.Error(message: error.localizedDescription)
        }
    }

    /// Displays success message after installation
    private func displayInstallSuccess(device: SimulatorDevice, appInfo: AppInfo, appPath: String) {
        stdout <<< "✓ App installation completed".green
        stdout <<< ""

        let deviceTypeName = DisplayFormat.deviceTypeName(from: device.deviceTypeIdentifier)
        let runtimeName = DisplayFormat.runtimeName(from: device.runtimeIdentifier)

        stdout <<< "Install Information:".bold
        stdout <<< "  App Name: \(appInfo.name)".dim

        if let bundleId = appInfo.bundleIdentifier {
            stdout <<< "  Bundle ID: \(bundleId)".dim
        }

        if let version = appInfo.version {
            stdout <<< "  Version: \(version)".dim
        }

        stdout <<< "  Path: \(appPath)".dim
        stdout <<< ""
        stdout <<< "Installed To:".bold
        stdout <<< "  Device: \(device.name)".dim
        stdout <<< "  Type: \(deviceTypeName)".dim
        stdout <<< "  Runtime: \(runtimeName)".dim
        stdout <<< "  UUID: \(device.udid)".dim

        stdout <<< ""
        stdout <<< "Tips:".dim
        stdout <<< "  • Verify the app in the simulator"
        if let bundleId = appInfo.bundleIdentifier {
            stdout <<< "  • To launch the app: xcrun simctl launch \(device.udid) \(bundleId)".dim
        }
    }
}

/// Helper struct to hold app information
private struct AppInfo {
    let name: String
    let bundleIdentifier: String?
    let version: String?
}
