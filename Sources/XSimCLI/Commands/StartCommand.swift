import Rainbow
import SwiftCLI

/// Command to start a simulator device
class StartCommand: Command {
    let name = "start"
    let shortDescription = "シミュレータを起動"
    let longDescription = """
    指定されたシミュレータデバイスを起動します。
    デバイスは名前またはUUIDで指定できます。

    例:
      xsim start "iPhone 15"                    # 名前で指定
      xsim start 12345678-1234-1234-1234-123456789012  # UUIDで指定
    """

    @Param var deviceIdentifier: String

    private var simulatorService: SimulatorService?

    init() {}

    func execute() throws {
        do {
            stdout <<< "シミュレータを起動しています...".dim

            // Start the simulator
            let simulatorService = try getService()
            try simulatorService.startSimulator(identifier: deviceIdentifier)

            // Get device info for confirmation
            let devices = try simulatorService.listDevices()
            if let device = findDevice(devices: devices, identifier: deviceIdentifier) {
                displayStartSuccess(device: device)
            } else {
                stdout <<< "✓ シミュレータ '\(deviceIdentifier)' を起動しました".green
            }

        } catch let error as SimulatorError {
            try handleSimulatorError(error)
        } catch {
            throw CLI.Error(message: "予期しないエラーが発生しました: \(error.localizedDescription)")
        }
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

        case let .deviceAlreadyRunning(identifier):
            stdout <<< "ℹ デバイス '\(identifier)' は既に起動しています".yellow

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

    /// Lazily creates the SimulatorService on first use
    private func getService() throws -> SimulatorService {
        if let service = simulatorService { return service }
        let service = try SimulatorService()
        simulatorService = service
        return service
    }

    /// Displays success message with device information
    private func displayStartSuccess(device: SimulatorDevice) {
        stdout <<< "✓ シミュレータを起動しました".green
        stdout <<< ""

        let deviceTypeName = extractDeviceTypeName(from: device.deviceTypeIdentifier)
        let runtimeName = extractRuntimeDisplayName(from: device.runtimeIdentifier)

        stdout <<< "デバイス情報:".bold
        stdout <<< "  名前: \(device.name)".dim
        stdout <<< "  タイプ: \(deviceTypeName)".dim
        stdout <<< "  ランタイム: \(runtimeName)".dim
        stdout <<< "  UUID: \(device.udid)".dim
        stdout <<< "  状態: \(formatDeviceState(device.state))".dim

        if device.state == .booting {
            stdout <<< ""
            stdout <<< "ヒント: シミュレータの起動が完了するまでしばらくお待ちください".dim
        }
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
