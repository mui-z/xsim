import Rainbow
import SwiftCLI

/// Command to create a new simulator device
class CreateCommand: Command {
    let name = "create"
    let shortDescription = "新しいシミュレータを作成"
    let longDescription = """
    新しいシミュレータデバイスを作成します。
    デバイスタイプとランタイムを指定して、カスタム名でシミュレータを作成できます。

    例:
      xsim create "My iPhone" com.apple.CoreSimulator.SimDeviceType.iPhone-15 com.apple.CoreSimulator.SimRuntime.iOS-17-0
      xsim create --list-types      # 利用可能なデバイスタイプを表示
      xsim create --list-runtimes   # 利用可能なランタイムを表示
    """

    @Param var deviceName: String?
    @Param var deviceType: String?
    @Param var runtime: String?

    @Flag("--list-types", description: "利用可能なデバイスタイプを一覧表示")
    var listDeviceTypes: Bool

    @Flag("--list-runtimes", description: "利用可能なランタイムを一覧表示")
    var listRuntimes: Bool

    private let simulatorService: SimulatorService

    init() throws {
        simulatorService = try SimulatorService()
    }

    func execute() throws {
        do {
            // Handle list flags first
            if listDeviceTypes {
                try displayAvailableDeviceTypes()
                return
            }

            if listRuntimes {
                try displayAvailableRuntimes()
                return
            }

            // Validate required parameters for creation
            guard let name = deviceName,
                  let deviceType,
                  let runtime
            else {
                stdout <<< "エラー: シミュレータ作成には名前、デバイスタイプ、ランタイムが必要です".red
                stdout <<< ""
                stdout <<< "使用方法:".bold
                stdout <<< "  xsim create <名前> <デバイスタイプ> <ランタイム>"
                stdout <<< ""
                stdout <<< "利用可能なオプションを確認:".dim
                stdout <<< "  xsim create --list-types      # デバイスタイプ一覧"
                stdout <<< "  xsim create --list-runtimes   # ランタイム一覧"
                throw CLI.Error(message: "")
            }

            stdout <<< "新しいシミュレータを作成しています...".dim

            // Create the simulator
            let uuid = try simulatorService.createSimulator(name: name, deviceType: deviceType, runtime: runtime)

            displayCreateSuccess(name: name, deviceType: deviceType, runtime: runtime, uuid: uuid)

        } catch let error as SimulatorError {
            try handleSimulatorError(error)
        } catch {
            throw CLI.Error(message: "予期しないエラーが発生しました: \(error.localizedDescription)")
        }
    }

    /// Displays available device types
    private func displayAvailableDeviceTypes() throws {
        let deviceTypes = try simulatorService.getAvailableDeviceTypes()

        if deviceTypes.isEmpty {
            stdout <<< "利用可能なデバイスタイプが見つかりません".yellow
            return
        }

        stdout <<< "利用可能なデバイスタイプ:".bold.blue
        stdout <<< ""

        // Group device types by category
        let iPhoneTypes = deviceTypes.filter(\.isiPhone)
        let iPadTypes = deviceTypes.filter(\.isiPad)
        let watchTypes = deviceTypes.filter(\.isWatch)
        let tvTypes = deviceTypes.filter(\.isTV)
        let otherTypes = deviceTypes.filter { !$0.isiPhone && !$0.isiPad && !$0.isWatch && !$0.isTV }

        if !iPhoneTypes.isEmpty {
            displayDeviceTypeCategory("iPhone", types: iPhoneTypes)
        }

        if !iPadTypes.isEmpty {
            displayDeviceTypeCategory("iPad", types: iPadTypes)
        }

        if !watchTypes.isEmpty {
            displayDeviceTypeCategory("Apple Watch", types: watchTypes)
        }

        if !tvTypes.isEmpty {
            displayDeviceTypeCategory("Apple TV", types: tvTypes)
        }

        if !otherTypes.isEmpty {
            displayDeviceTypeCategory("その他", types: otherTypes)
        }

        stdout <<< ""
        stdout <<< "使用例:".dim
        stdout <<< "  xsim create \"My iPhone\" \(iPhoneTypes.first?.identifier ?? "DEVICE_TYPE") RUNTIME_ID"
    }

    /// Displays available runtimes
    private func displayAvailableRuntimes() throws {
        let runtimes = try simulatorService.getAvailableRuntimes()

        if runtimes.isEmpty {
            stdout <<< "利用可能なランタイムが見つかりません".yellow
            return
        }

        stdout <<< "利用可能なランタイム:".bold.blue
        stdout <<< ""

        // Group runtimes by platform
        let iOSRuntimes = runtimes.filter(\.isiOS)
        let watchOSRuntimes = runtimes.filter(\.isWatchOS)
        let tvOSRuntimes = runtimes.filter(\.isTvOS)
        let otherRuntimes = runtimes.filter { !$0.isiOS && !$0.isWatchOS && !$0.isTvOS }

        if !iOSRuntimes.isEmpty {
            displayRuntimeCategory("iOS", runtimes: iOSRuntimes)
        }

        if !watchOSRuntimes.isEmpty {
            displayRuntimeCategory("watchOS", runtimes: watchOSRuntimes)
        }

        if !tvOSRuntimes.isEmpty {
            displayRuntimeCategory("tvOS", runtimes: tvOSRuntimes)
        }

        if !otherRuntimes.isEmpty {
            displayRuntimeCategory("その他", runtimes: otherRuntimes)
        }

        stdout <<< ""
        stdout <<< "使用例:".dim
        stdout <<< "  xsim create \"My iPhone\" DEVICE_TYPE \(iOSRuntimes.first?.identifier ?? "RUNTIME_ID")"
    }

    /// Displays a category of device types
    private func displayDeviceTypeCategory(_ categoryName: String, types: [DeviceType]) {
        stdout <<< "\(categoryName):".bold

        for deviceType in types.sorted(by: { $0.displayName < $1.displayName }) {
            let availability = "✓".green
            stdout <<< "  \(availability) \(deviceType.displayName.padding(toLength: 25, withPad: " ", startingAt: 0)) \(deviceType.identifier.dim)"
        }

        stdout <<< ""
    }

    /// Displays a category of runtimes
    private func displayRuntimeCategory(_ categoryName: String, runtimes: [Runtime]) {
        stdout <<< "\(categoryName):".bold

        let sortedRuntimes = runtimes.sorted { runtime1, runtime2 in
            // Sort by major version descending, then by name
            if let v1 = runtime1.majorVersion, let v2 = runtime2.majorVersion, v1 != v2 {
                return v1 > v2
            }
            return runtime1.displayName < runtime2.displayName
        }

        for runtime in sortedRuntimes {
            let availability = runtime.isAvailable ? "✓".green : "✗".red
            let status = runtime.isAvailable ? "" : " (利用不可)".red
            stdout <<< "  \(availability) \(runtime.displayName.padding(toLength: 20, withPad: " ", startingAt: 0))\(status) \(runtime.identifier.dim)"
        }

        stdout <<< ""
    }

    /// Handles specific simulator errors with helpful messages
    private func handleSimulatorError(_ error: SimulatorError) throws {
        switch error {
        case let .invalidDeviceType(deviceType):
            stdout <<< "✗ 無効なデバイスタイプ: \(deviceType)".red
            stdout <<< ""
            stdout <<< "利用可能なデバイスタイプを確認するには:".dim
            stdout <<< "  xsim create --list-types".cyan
            throw CLI.Error(message: "")

        case let .invalidRuntime(runtime):
            stdout <<< "✗ 無効なランタイム: \(runtime)".red
            stdout <<< ""
            stdout <<< "利用可能なランタイムを確認するには:".dim
            stdout <<< "  xsim create --list-runtimes".cyan
            throw CLI.Error(message: "")

        default:
            throw CLI.Error(message: error.localizedDescription)
        }
    }

    /// Displays success message after creation
    private func displayCreateSuccess(name: String, deviceType: String, runtime: String, uuid: String) {
        stdout <<< "✓ 新しいシミュレータを作成しました".green
        stdout <<< ""

        let deviceTypeName = extractDeviceTypeName(from: deviceType)
        let runtimeName = extractRuntimeDisplayName(from: runtime)

        stdout <<< "作成されたシミュレータ:".bold
        stdout <<< "  名前: \(name)".dim
        stdout <<< "  タイプ: \(deviceTypeName)".dim
        stdout <<< "  ランタイム: \(runtimeName)".dim
        stdout <<< "  UUID: \(uuid)".dim

        stdout <<< ""
        stdout <<< "次のステップ:".dim
        stdout <<< "  • シミュレータを起動: xsim start \"\(name)\"".dim
        stdout <<< "  • すべてのシミュレータを確認: xsim list".dim
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
