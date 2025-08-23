import Rainbow
import SwiftCLI

/// Command to stop simulator devices
class StopCommand: Command {
    let name = "stop"
    let shortDescription = "シミュレータを停止"
    let longDescription = """
    指定されたシミュレータデバイスを停止します。
    デバイスを指定しない場合は、実行中のすべてのシミュレータを停止します。

    例:
      xsim stop                                 # すべての実行中シミュレータを停止
      xsim stop "iPhone 15"                     # 特定のデバイスを停止
      xsim stop 12345678-1234-1234-1234-123456789012  # UUIDで指定
    """

    @Param var deviceIdentifier: String?

    private var simulatorService: SimulatorService?

    init() {}

    func execute() throws {
        do {
            if let identifier = deviceIdentifier {
                // Stop specific device
                try stopSpecificDevice(identifier: identifier)
            } else {
                // Stop all running devices
                try stopAllDevices()
            }

        } catch let error as SimulatorError {
            try handleSimulatorError(error)
        } catch {
            throw CLI.Error(message: "予期しないエラーが発生しました: \(error.localizedDescription)")
        }
    }

    /// Stops a specific device
    private func stopSpecificDevice(identifier: String) throws {
        stdout <<< "シミュレータを停止しています...".dim

        // Get device info before stopping
        let simulatorService = try getService()
        let devices = try simulatorService.listDevices()
        guard let device = findDevice(devices: devices, identifier: identifier) else {
            throw SimulatorError.deviceNotFound(identifier)
        }

        // Stop the device
        try simulatorService.stopSimulator(identifier: identifier)

        displayStopSuccess(device: device)
    }

    /// Stops all running devices
    private func stopAllDevices() throws {
        // Get list of running devices before stopping
        let simulatorService = try getService()
        let devices = try simulatorService.listDevices()
        let runningDevices = devices.filter(\.state.isRunning)

        if runningDevices.isEmpty {
            stdout <<< "実行中のシミュレータはありません".yellow
            return
        }

        stdout <<< "実行中のすべてのシミュレータを停止しています...".dim

        // Stop all devices
        try simulatorService.stopSimulator(identifier: nil)

        displayStopAllSuccess(stoppedDevices: runningDevices)
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

        case let .deviceNotRunning(identifier):
            stdout <<< "ℹ デバイス '\(identifier)' は既に停止しています".yellow

            // Try to get device info to show current status
            do {
                let simulatorService = try getService()
                let devices = try simulatorService.listDevices()
                if let device = findDevice(devices: devices, identifier: identifier) {
                    displayDeviceStatus(device: device)
                }
            } catch {
                // Ignore errors when trying to get device info
            }

        default:
            throw CLI.Error(message: error.localizedDescription)
        }
    }

    /// Displays success message for stopping a specific device
    private func displayStopSuccess(device: SimulatorDevice) {
        stdout <<< "✓ シミュレータを停止しました".green
        stdout <<< ""

        let deviceTypeName = extractDeviceTypeName(from: device.deviceTypeIdentifier)
        let runtimeName = extractRuntimeDisplayName(from: device.runtimeIdentifier)

        stdout <<< "デバイス情報:".bold
        stdout <<< "  名前: \(device.name)".dim
        stdout <<< "  タイプ: \(deviceTypeName)".dim
        stdout <<< "  ランタイム: \(runtimeName)".dim
        stdout <<< "  UUID: \(device.udid)".dim
    }

    /// Displays success message for stopping all devices
    private func displayStopAllSuccess(stoppedDevices: [SimulatorDevice]) {
        stdout <<< "✓ すべてのシミュレータを停止しました".green
        stdout <<< ""

        stdout <<< "停止したデバイス (\(stoppedDevices.count)台):".bold
        for device in stoppedDevices.sorted(by: { $0.name < $1.name }) {
            let deviceTypeName = extractDeviceTypeName(from: device.deviceTypeIdentifier)
            stdout <<< "  • \(device.name) (\(deviceTypeName))".dim
        }

        stdout <<< ""
        stdout <<< "ヒント: シミュレータを再起動するには 'xsim start <device>' を使用してください".dim
    }

    /// Displays current device status
    private func displayDeviceStatus(device: SimulatorDevice) {
        stdout <<< ""
        stdout <<< "現在の状態:".dim
        stdout <<< "  名前: \(device.name)"
        stdout <<< "  状態: \(formatDeviceState(device.state))"
        stdout <<< "  UUID: \(device.udid)".dim
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

    /// Formats the device state with appropriate colors
    private func formatDeviceState(_ state: SimulatorState) -> String {
        switch state {
        case .booted:
            "起動中".green
        case .booting:
            "起動処理中".yellow
        case .shutdown:
            "停止中".dim
        case .shuttingDown:
            "停止処理中".yellow
        }
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

// Lazy service accessor
extension StopCommand {
    private func getService() throws -> SimulatorService {
        if let service = simulatorService { return service }
        let service = try SimulatorService()
        simulatorService = service
        return service
    }
}
