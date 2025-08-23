import Rainbow
import SwiftCLI

/// Command to delete a simulator device
class DeleteCommand: Command {
    let name = "delete"
    let shortDescription = "シミュレータを削除"
    let longDescription = """
    指定されたシミュレータデバイスを削除します。
    実行中のシミュレータは自動的に停止されてから削除されます。
    この操作は元に戻すことができません。

    例:
      xsim delete "iPhone 15"                  # 名前で指定
      xsim delete 12345678-1234-1234-1234-123456789012  # UUIDで指定
    """

    @Param var deviceIdentifier: String

    @Flag("-f", "--force", description: "確認なしで削除を実行")
    var force: Bool

    private var simulatorService: SimulatorService?

    init() {}

    func execute() throws {
        do {
            // Get device info before deleting
            let simulatorService = try getService()
            let devices = try simulatorService.listDevices()
            guard let device = findDevice(devices: devices, identifier: deviceIdentifier) else {
                throw SimulatorError.deviceNotFound(deviceIdentifier)
            }

            // Show warning and device info
            displayDeleteWarning(device: device)

            // Confirm the delete operation unless forced
            if !force, !confirmDelete(device: device) {
                stdout <<< "削除操作をキャンセルしました".yellow
                return
            }

            stdout <<< "シミュレータを削除しています...".dim

            // Delete the device
            try simulatorService.deleteSimulator(identifier: deviceIdentifier)

            displayDeleteSuccess(device: device)

        } catch let error as SimulatorError {
            try handleSimulatorError(error)
        } catch {
            throw CLI.Error(message: "予期しないエラーが発生しました: \(error.localizedDescription)")
        }
    }

    /// Displays warning message before deletion
    private func displayDeleteWarning(device: SimulatorDevice) {
        if force {
            return // Skip warning if forced
        }

        stdout <<< "⚠️  削除操作の確認".yellow.bold
        stdout <<< ""

        let deviceTypeName = extractDeviceTypeName(from: device.deviceTypeIdentifier)
        let runtimeName = extractRuntimeDisplayName(from: device.runtimeIdentifier)

        stdout <<< "以下のシミュレータを削除します:".bold
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
        stdout <<< "  • シミュレータデバイス"
        stdout <<< "  • すべてのアプリとデータ"
        stdout <<< "  • システム設定"
        stdout <<< "  • ログファイル"
        stdout <<< ""
        stdout <<< "この操作は元に戻すことができません。".red.bold
    }

    /// Confirms the delete operation with user
    private func confirmDelete(device _: SimulatorDevice) -> Bool {
        stdout <<< "本当に削除しますか？ (y/N): ".bold

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

    /// Displays success message after deletion
    private func displayDeleteSuccess(device: SimulatorDevice) {
        stdout <<< "✓ シミュレータを削除しました".green
        stdout <<< ""

        let deviceTypeName = extractDeviceTypeName(from: device.deviceTypeIdentifier)
        let runtimeName = extractRuntimeDisplayName(from: device.runtimeIdentifier)

        stdout <<< "削除されたシミュレータ:".bold
        stdout <<< "  名前: \(device.name)".dim
        stdout <<< "  タイプ: \(deviceTypeName)".dim
        stdout <<< "  ランタイム: \(runtimeName)".dim
        stdout <<< "  UUID: \(device.udid)".dim

        stdout <<< ""
        stdout <<< "ヒント:".dim
        stdout <<< "  • 残りのシミュレータを確認: xsim list".dim
        stdout <<< "  • 新しいシミュレータを作成: xsim create <name> <type> <runtime>".dim

        // Show available device types and runtimes for convenience
        stdout <<< "  • 利用可能なデバイスタイプ: xsim create --list-types".dim
        stdout <<< "  • 利用可能なランタイム: xsim create --list-runtimes".dim
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
extension DeleteCommand {
    private func getService() throws -> SimulatorService {
        if let service = simulatorService { return service }
        let service = try SimulatorService()
        simulatorService = service
        return service
    }
}
