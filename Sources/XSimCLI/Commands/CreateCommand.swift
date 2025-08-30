import Rainbow
import SwiftCLI

/// Command to create a new simulator device
class CreateCommand: BaseSimCommand, Command {
    let name = "create"
    let shortDescription = "Create a new simulator"
    let longDescription = """
    Creates a new simulator device.
    Specify the device type and runtime, and optionally a custom name.

    Examples:
      xsim create "My iPhone" com.apple.CoreSimulator.SimDeviceType.iPhone-15 com.apple.CoreSimulator.SimRuntime.iOS-17-0
      xsim create "My iPhone" "iPhone 16 Pro" "iOS 26.0"
      xsim create --list-types      # show available device types
      xsim create --list-runtimes   # show available runtimes
    """

    @Param var deviceName: String?
    @Param var deviceType: String?
    @Param var runtime: String?

    @Flag("--list-types", description: "List available device types")
    var listDeviceTypes: Bool

    @Flag("--list-runtimes", description: "List available runtimes")
    var listRuntimes: Bool

    override init() {}

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
                stdout <<< "Error: Name, device type, and runtime are required to create a simulator".red
                stdout <<< ""
                stdout <<< "Usage:".bold
                stdout <<< "  xsim create <name> <device-type> <runtime>"
                stdout <<< ""
                stdout <<< "See available options:".dim
                stdout <<< "  xsim create --list-types      # device types"
                stdout <<< "  xsim create --list-runtimes   # runtimes"
                throw CLI.Error(message: "")
            }

            stdout <<< "Creating a new simulator...".dim

            // Create the simulator
            let simulatorService = try getService()
            let uuid = try simulatorService.createSimulator(name: name, deviceType: deviceType, runtime: runtime)

            // 生成直後に実体を取得して、表示用に正規の識別子から名前を出す
            if let created = try? simulatorService.listDevices().first(where: { $0.udid == uuid }) {
                displayCreateSuccess(name: name, deviceType: created.deviceTypeIdentifier, runtime: created.runtimeIdentifier, uuid: uuid)
            } else {
                // 取得できない場合は従来の表示にフォールバック
                displayCreateSuccess(name: name, deviceType: deviceType, runtime: runtime, uuid: uuid)
            }

        } catch let error as SimulatorError {
            try handleSimulatorError(error)
        } catch {
            throw CLI.Error(message: "An unexpected error occurred: \(error.localizedDescription)")
        }
    }

    /// Displays available device types
    private func displayAvailableDeviceTypes() throws {
        let simulatorService = try getService()
        let deviceTypes = try simulatorService.getAvailableDeviceTypes()

        if deviceTypes.isEmpty {
            stdout <<< "No device types found".yellow
            return
        }

        stdout <<< "Available device types:".bold.blue
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
            displayDeviceTypeCategory("Other", types: otherTypes)
        }

        stdout <<< ""
        stdout <<< "Example:".dim
        stdout <<< "  xsim create \"My iPhone\" \(iPhoneTypes.first?.identifier ?? "DEVICE_TYPE") RUNTIME_ID"
    }

    /// Displays available runtimes
    private func displayAvailableRuntimes() throws {
        let simulatorService = try getService()
        let runtimes = try simulatorService.getAvailableRuntimes()
        print("FINISH get runtimes")

        if runtimes.isEmpty {
            stdout <<< "No runtimes found".yellow
            return
        }

        stdout <<< "Available runtimes:".bold.blue
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
            displayRuntimeCategory("Other", runtimes: otherRuntimes)
        }

        stdout <<< ""
        stdout <<< "Example:".dim
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
            let status = runtime.isAvailable ? "" : " (Unavailable)".red
            stdout <<< "  \(availability) \(runtime.displayName.padding(toLength: 20, withPad: " ", startingAt: 0))\(status) \(runtime.identifier.dim)"
        }

        stdout <<< ""
    }

    /// Handles specific simulator errors with helpful messages
    private func handleSimulatorError(_ error: SimulatorError) throws {
        switch error {
        case let .invalidDeviceType(deviceType):
            stdout <<< "✗ Invalid device type: \(deviceType)".red
            stdout <<< ""
            stdout <<< "To list available device types:".dim
            stdout <<< "  xsim create --list-types".cyan
            throw CLI.Error(message: "")

        case let .invalidRuntime(runtime):
            stdout <<< "✗ Invalid runtime: \(runtime)".red
            stdout <<< ""
            stdout <<< "To list available runtimes:".dim
            stdout <<< "  xsim create --list-runtimes".cyan
            throw CLI.Error(message: "")

        default:
            throw CLI.Error(message: error.localizedDescription)
        }
    }

    /// Displays success message after creation
    private func displayCreateSuccess(name: String, deviceType: String, runtime: String, uuid: String) {
        stdout <<< "✓ Created a new simulator".green
        stdout <<< ""

        let deviceTypeName = DisplayFormat.deviceTypeName(from: deviceType)
        let runtimeName = DisplayFormat.runtimeName(from: runtime)

        stdout <<< "Created simulator:".bold
        stdout <<< "  Name: \(name)".dim
        stdout <<< "  Type: \(deviceTypeName)".dim
        stdout <<< "  Runtime: \(runtimeName)".dim
        stdout <<< "  UUID: \(uuid)".dim

        stdout <<< ""
        stdout <<< "Next steps:".dim
        stdout <<< "  • Start the simulator: xsim start \"\(name)\"".dim
        stdout <<< "  • List all simulators: xsim list".dim
    }
}
