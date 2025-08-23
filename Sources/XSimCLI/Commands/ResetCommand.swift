import Rainbow
import SwiftCLI

/// Command to reset (erase) a simulator device
class ResetCommand: Command {
    let name = "reset"
    let shortDescription = "シミュレータをリセット"
    let longDescription = """
    指定されたシミュレータデバイスのすべてのデータと設定を消去します。
    この操作により、シミュレータは初期状態に戻ります。
    実行中のシミュレータは自動的に停止されてからリセットされます。

    例:
      xsim reset "iPhone 15"                   # 名前で指定
      xsim reset 12345678-1234-1234-1234-123456789012  # UUIDで指定
    """

    @Param var deviceIdentifier: String

    private let simulatorService: SimulatorService

    init() throws {
        simulatorService = try SimulatorService()
    }

    func execute() throws {
        do {
            // Get device info before resetting
            let devices = try simulatorService.listDevices()
            guard let device = findDevice(devices: devices, identifier: deviceIdentifier) else {
                throw SimulatorError.deviceNotFound(deviceIdentifier)
            }

            // Show warning and device info
            displayResetWarning(device: device)

            // Confirm the reset operation
            if !confirmReset(device: device) {
                stdout <<< "リセット操作をキャンセルしました".yellow
                return
            }

            stdout <<< "シミュレータをリセットしています...".dim

            // Reset the device
            try simulatorService.resetSimulator(identifier: deviceIdentifier)

            displayResetSuccess(device: device)

        } catch let error as SimulatorError {
            try handleSimulatorError(error)
        } catch {
            throw CLI.Error(message: "予期しないエラーが発生しました: \(error.localizedDescription)")
        }
    }

    /// Displays warning message before reset
    private func displayResetWarning(device: SimulatorDevice) {
        stdout <<< "⚠️  リセット操作の確認".yellow.bold
        stdout <<< ""

        let deviceTypeName = extractDeviceTypeName(from: device.deviceTypeIdentifier)
        let runtimeName = extractRuntimeDisplayName(from: device.runtimeIdentifier)

        stdout <<< "以下のシミュレータをリセットします:".bold
        stdout <<< "  名前: \(device.name)"
        stdout <<< "  タイプ: \(deviceTypeName)"
        stdout <<< "  ランタイム: \(runtimeName)"
        stdout <<< "  UUID: \(device.udid)".dim

        if device.state.isRunning {
            stdout <<< "  現在の状態: \(formatDeviceState(device.state))"
            stdout <<< ""
            stdout <<< "注意: 実行中のシミュレータは自動的に停止されます".yellow
        }

        stdout <<< ""
        stdout <<< "この操作により以下が削除されます:".red
        stdout <<< "  • すべてのアプリとデータ"
        stdout <<< "  • システム設定"
        stdout <<< "  • キーチェーンデータ"
        stdout <<< "  • ログファイル"
        stdout <<< ""
        stdout <<< "この操作は元に戻すことができません。".red.bold
    }

    /// Confirms the reset operation with user
    private func confirmReset(device _: SimulatorDevice) -> Bool {
        stdout <<< "本当にリセットしますか？ (y/N): ".bold

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }

        return input == "y" || input == "yes"
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

        default:
            throw CLI.Error(message: error.localizedDescription)
        }
    }

    /// Displays success message after reset
    private func displayResetSuccess(device: SimulatorDevice) {
        stdout <<< "✓ シミュレータをリセットしました".green
        stdout <<< ""

        let deviceTypeName = extractDeviceTypeName(from: device.deviceTypeIdentifier)
        let runtimeName = extractRuntimeDisplayName(from: device.runtimeIdentifier)

        stdout <<< "リセット完了:".bold
        stdout <<< "  名前: \(device.name)".dim
        stdout <<< "  タイプ: \(deviceTypeName)".dim
        stdout <<< "  ランタイム: \(runtimeName)".dim
        stdout <<< "  UUID: \(device.udid)".dim
        stdout <<< ""
        stdout <<< "シミュレータは初期状態に戻りました。".green
        stdout <<< ""
        stdout <<< "ヒント:".dim
        stdout <<< "  • シミュレータを起動するには: xsim start \"\(device.name)\"".dim
        stdout <<< "  • 他のシミュレータを確認するには: xsim list".dim
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
