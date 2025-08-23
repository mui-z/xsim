import Rainbow
import SwiftCLI

/// Command to list available simulator devices
class ListCommand: Command {
    let name = "list"
    let shortDescription = "利用可能なシミュレータを一覧表示"
    let longDescription = """
    利用可能なシミュレータデバイスを一覧表示します。
    デバイス名、UUID、現在のステータス、デバイスタイプ、iOSバージョンが表示されます。

    例:
      xsim list                    # すべてのデバイスを表示
      xsim list --running          # 実行中のデバイスのみ表示
      xsim list --available        # 利用可能なデバイスのみ表示
    """

    @Flag("-r", "--running", description: "実行中のシミュレータのみ表示")
    var showRunningOnly: Bool

    @Flag("-a", "--available", description: "利用可能なシミュレータのみ表示")
    var showAvailableOnly: Bool

    private let simulatorService: SimulatorService

    init() throws {
        simulatorService = try SimulatorService()
    }

    func execute() throws {
        do {
            let devices = try simulatorService.listDevices()

            // Filter devices based on flags
            let filteredDevices = filterDevices(devices)

            if filteredDevices.isEmpty {
                displayNoDevicesMessage()
                return
            }

            displayDevices(filteredDevices)

        } catch let error as SimulatorError {
            throw CLI.Error(message: error.localizedDescription)
        } catch {
            throw CLI.Error(message: "予期しないエラーが発生しました: \(error.localizedDescription)")
        }
    }

    /// Filters devices based on command flags
    private func filterDevices(_ devices: [SimulatorDevice]) -> [SimulatorDevice] {
        var filtered = devices

        if showRunningOnly {
            filtered = filtered.filter(\.state.isRunning)
        }

        if showAvailableOnly {
            filtered = filtered.filter(\.isAvailable)
        }

        return filtered
    }

    /// Displays a message when no devices are found
    private func displayNoDevicesMessage() {
        if showRunningOnly {
            stdout <<< "実行中のシミュレータはありません。".yellow
            stdout <<< "シミュレータを起動するには: xsim start <device>".dim
        } else if showAvailableOnly {
            stdout <<< "利用可能なシミュレータはありません。".yellow
            stdout <<< "新しいシミュレータを作成するには: xsim create <name> <type> <runtime>".dim
        } else {
            stdout <<< "シミュレータが見つかりません。".yellow
            stdout <<< "新しいシミュレータを作成するには: xsim create <name> <type> <runtime>".dim
        }
    }

    /// Displays devices in a formatted table
    private func displayDevices(_ devices: [SimulatorDevice]) {
        // Group devices by runtime for better organization
        let groupedDevices = Dictionary(grouping: devices) { device in
            extractRuntimeDisplayName(from: device.runtimeIdentifier)
        }

        let sortedRuntimes = groupedDevices.keys.sorted()

        for runtime in sortedRuntimes {
            guard let devicesForRuntime = groupedDevices[runtime] else { continue }

            // Display runtime header
            stdout <<< ""
            stdout <<< "== \(runtime) ==".bold.blue

            // Display table header
            displayTableHeader()

            // Display devices for this runtime
            let sortedDevices = devicesForRuntime.sorted { $0.name < $1.name }
            for device in sortedDevices {
                displayDeviceRow(device)
            }
        }

        // Display summary
        displaySummary(devices)
    }

    /// Displays the table header
    private func displayTableHeader() {
        let header = String(format: "%-25s %-8s %-20s %s", "名前", "状態", "デバイスタイプ", "UUID")
        stdout <<< header.bold
        stdout <<< String(repeating: "-", count: 80).dim
    }

    /// Displays a single device row
    private func displayDeviceRow(_ device: SimulatorDevice) {
        let deviceTypeName = extractDeviceTypeName(from: device.deviceTypeIdentifier)
        let stateDisplay = formatDeviceState(device.state, isAvailable: device.isAvailable)

        let row = String(format: "%-25s %-8s %-20s %s",
                         truncateString(device.name, maxLength: 24),
                         stateDisplay,
                         truncateString(deviceTypeName, maxLength: 19),
                         device.udid.dim)

        stdout <<< row
    }

    /// Formats the device state with appropriate colors
    private func formatDeviceState(_ state: SimulatorState, isAvailable: Bool) -> String {
        if !isAvailable {
            return "無効".red
        }

        switch state {
        case .booted:
            return "起動中".green
        case .booting:
            return "起動処理中".yellow
        case .shutdown:
            return "停止中".dim
        case .shuttingDown:
            return "停止処理中".yellow
        }
    }

    /// Displays a summary of the devices
    private func displaySummary(_ devices: [SimulatorDevice]) {
        stdout <<< ""

        let totalCount = devices.count
        let runningCount = devices.count(where: { $0.state.isRunning })
        let availableCount = devices.count(where: { $0.isAvailable })

        stdout <<< "合計: \(totalCount)台, 実行中: \(runningCount)台, 利用可能: \(availableCount)台".dim

        if runningCount == 0, !showRunningOnly {
            stdout <<< ""
            stdout <<< "ヒント: シミュレータを起動するには 'xsim start <device>' を使用してください".dim
        }
    }

    /// Extracts a display-friendly runtime name from the runtime identifier
    private func extractRuntimeDisplayName(from identifier: String) -> String {
        // Convert identifiers like "com.apple.CoreSimulator.SimRuntime.iOS-17-0" to "iOS 17.0"
        let components = identifier.components(separatedBy: ".")
        guard let lastComponent = components.last else {
            return identifier
        }

        // Handle iOS, watchOS, tvOS patterns
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
        // Convert identifiers like "com.apple.CoreSimulator.SimDeviceType.iPhone-15" to "iPhone 15"
        let components = identifier.components(separatedBy: ".")
        guard let lastComponent = components.last else {
            return identifier
        }

        return lastComponent.replacingOccurrences(of: "-", with: " ")
    }

    /// Truncates a string to the specified maximum length
    private func truncateString(_ string: String, maxLength: Int) -> String {
        if string.count <= maxLength {
            return string
        }

        let truncated = String(string.prefix(maxLength - 3))
        return truncated + "..."
    }
}
