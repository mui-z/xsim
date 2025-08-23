import Foundation
import Rainbow
import SwiftCLI

/// Command to install an app on a simulator device
class InstallCommand: Command {
    let name = "install"
    let shortDescription = "シミュレータにアプリをインストール"
    let longDescription = """
    指定されたシミュレータデバイスにアプリケーションをインストールします。
    アプリは.appバンドルのパスで指定し、対象デバイスは名前またはUUIDで指定します。
    デバイスが停止している場合は、自動的に起動されます。

    例:
      xsim install "iPhone 15" /path/to/MyApp.app
      xsim install 12345678-1234-1234-1234-123456789012 ~/Desktop/MyApp.app
    """

    @Param var deviceIdentifier: String
    @Param var appBundlePath: String

    private let simulatorService: SimulatorService

    init() throws {
        simulatorService = try SimulatorService()
    }

    func execute() throws {
        do {
            // Expand tilde in path
            let expandedPath = expandPath(appBundlePath)

            // Validate app bundle path first
            try validateAppBundle(at: expandedPath)

            // Get device info
            let devices = try simulatorService.listDevices()
            guard let device = findDevice(devices: devices, identifier: deviceIdentifier) else {
                throw SimulatorError.deviceNotFound(deviceIdentifier)
            }

            // Check if device needs to be started
            if !device.state.isRunning {
                stdout <<< "デバイスが停止しています。起動しています...".dim
                try simulatorService.startSimulator(identifier: deviceIdentifier)
                stdout <<< "✓ デバイスを起動しました".green
                stdout <<< ""
            }

            // Get app info
            let appInfo = try extractAppInfo(from: expandedPath)

            stdout <<< "アプリをインストールしています...".dim

            // Install the app
            try simulatorService.installApp(bundlePath: expandedPath, deviceIdentifier: deviceIdentifier)

            displayInstallSuccess(device: device, appInfo: appInfo, appPath: expandedPath)

        } catch let error as SimulatorError {
            try handleSimulatorError(error)
        } catch {
            throw CLI.Error(message: "予期しないエラーが発生しました: \(error.localizedDescription)")
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
            stdout <<< "✗ デバイス '\(identifier)' が見つかりません".red
            stdout <<< ""
            stdout <<< "利用可能なデバイスを確認するには:".dim
            stdout <<< "  xsim list".cyan
            throw CLI.Error(message: "")

        case let .appBundleNotFound(path):
            stdout <<< "✗ アプリバンドルが見つかりません: \(path)".red
            stdout <<< ""
            stdout <<< "確認事項:".dim
            stdout <<< "  • パスが正しいか確認してください"
            stdout <<< "  • ファイルが.app拡張子を持っているか確認してください"
            stdout <<< "  • Info.plistファイルが存在するか確認してください"
            throw CLI.Error(message: "")

        case let .deviceNotRunning(identifier):
            stdout <<< "✗ デバイス '\(identifier)' が起動していません".red
            stdout <<< ""
            stdout <<< "デバイスを起動してから再試行してください:".dim
            stdout <<< "  xsim start \"\(identifier)\"".cyan
            throw CLI.Error(message: "")

        default:
            throw CLI.Error(message: error.localizedDescription)
        }
    }

    /// Displays success message after installation
    private func displayInstallSuccess(device: SimulatorDevice, appInfo: AppInfo, appPath: String) {
        stdout <<< "✓ アプリのインストールが完了しました".green
        stdout <<< ""

        let deviceTypeName = extractDeviceTypeName(from: device.deviceTypeIdentifier)
        let runtimeName = extractRuntimeDisplayName(from: device.runtimeIdentifier)

        stdout <<< "インストール情報:".bold
        stdout <<< "  アプリ名: \(appInfo.name)".dim

        if let bundleId = appInfo.bundleIdentifier {
            stdout <<< "  バンドルID: \(bundleId)".dim
        }

        if let version = appInfo.version {
            stdout <<< "  バージョン: \(version)".dim
        }

        stdout <<< "  パス: \(appPath)".dim
        stdout <<< ""
        stdout <<< "インストール先:".bold
        stdout <<< "  デバイス: \(device.name)".dim
        stdout <<< "  タイプ: \(deviceTypeName)".dim
        stdout <<< "  ランタイム: \(runtimeName)".dim
        stdout <<< "  UUID: \(device.udid)".dim

        stdout <<< ""
        stdout <<< "ヒント:".dim
        stdout <<< "  • シミュレータでアプリを確認してください"
        if let bundleId = appInfo.bundleIdentifier {
            stdout <<< "  • アプリを起動するには: xcrun simctl launch \(device.udid) \(bundleId)".dim
        }
    }

    /// Finds a device by identifier (name or UUID)
    private func findDevice(devices: [SimulatorDevice], identifier: String) -> SimulatorDevice? {
        // First try to find by UUID
        if let device = devices.first(where: { $0.udid == identifier }) {
            return device
        }

        // Then try to find by name
        return devices.first(where: { $0.name == identifier })
    }

    /// Extracts a display-friendly runtime name from the runtime identifier
    private func extractRuntimeDisplayName(from identifier: String) -> String {
        let components = identifier.components(separatedBy: ".")
        guard let lastComponent = components.last else {
            return identifier
        }

        if lastComponent.hasPrefix("iOS-") {
            let version = lastComponent.replacingOccurrences(of: "iOS-", with: "").replacingOccurrences(of: "-", with: ".")
            return "iOS \(version)"
        } else if lastComponent.hasPrefix("watchOS-") {
            let version = lastComponent.replacingOccurrences(of: "watchOS-", with: "").replacingOccurrences(of: "-", with: ".")
            return "watchOS \(version)"
        } else if lastComponent.hasPrefix("tvOS-") {
            let version = lastComponent.replacingOccurrences(of: "tvOS-", with: "").replacingOccurrences(of: "-", with: ".")
            return "tvOS \(version)"
        }

        return lastComponent
    }

    /// Extracts a display-friendly device type name from the device type identifier
    private func extractDeviceTypeName(from identifier: String) -> String {
        let components = identifier.components(separatedBy: ".")
        guard let lastComponent = components.last else {
            return identifier
        }

        return lastComponent.replacingOccurrences(of: "-", with: " ")
    }
}

/// Helper struct to hold app information
private struct AppInfo {
    let name: String
    let bundleIdentifier: String?
    let version: String?
}
