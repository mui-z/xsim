import Rainbow
import SwiftCLI

/// Command to list available simulator devices
class ListCommand: Command {
    let name = "list"
    let shortDescription = "List available simulators"
    let longDescription = """
    Lists available simulator devices.
    Displays device name, UUID, current status, device type, and platform version.

    Examples:
      xsim list                    # show all devices
      xsim list --running          # only running devices
      xsim list --available        # only available devices
      xsim list --resolve-names    # resolve runtime/type names via JSON
    """

    @Flag("-r", "--running", description: "Show only running simulators")
    var showRunningOnly: Bool

    @Flag("-a", "--available", description: "Show only available simulators")
    var showAvailableOnly: Bool

    @Flag("--resolve-names", description: "Resolve runtime/device type names via JSON (extra simctl calls)")
    var resolveNames: Bool

    private var simulatorService: SimulatorService?

    init() {}

    func execute() throws {
        do {
            let simulatorService = try getService()
            let devices = try simulatorService.listDevices()

            // Optionally build display-name maps using simctl's JSON outputs
            var runtimeNameById: [String: String] = [:]
            var deviceTypeNameById: [String: String] = [:]
            if resolveNames {
                do {
                    let runtimes = try simulatorService.getAvailableRuntimes()
                    runtimeNameById = Dictionary(uniqueKeysWithValues: runtimes.map { ($0.identifier, $0.displayName) })
                    let types = try simulatorService.getAvailableDeviceTypes()
                    deviceTypeNameById = Dictionary(uniqueKeysWithValues: types.map { ($0.identifier, $0.displayName) })
                } catch {
                    // Fallback to heuristic parsing if lookup fails
                    runtimeNameById = [:]
                    deviceTypeNameById = [:]
                }
            }

            // Debug: Print counts before filtering
            print("Debug: Total devices fetched: \(devices.count). runningOnly=\(showRunningOnly), availableOnly=\(showAvailableOnly)")

            // Filter devices based on flags
            let filteredDevices = filterDevices(devices)

            if filteredDevices.isEmpty {
                // Debug: No devices after filtering
                print("Debug: No devices after filtering. Original=\(devices.count)")
                displayNoDevicesMessage()
                return
            }

            displayDevices(filteredDevices, runtimeNameById: runtimeNameById, deviceTypeNameById: deviceTypeNameById)

        } catch let error as SimulatorError {
            throw CLI.Error(message: error.localizedDescription)
        } catch {
            throw CLI.Error(message: "An unexpected error occurred: \(error.localizedDescription)")
        }
    }

    /// Lazily creates the SimulatorService on first use
    private func getService() throws -> SimulatorService {
        if let service = simulatorService { return service }
        let service = try SimulatorService()
        simulatorService = service
        return service
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
            stdout <<< "No simulators are running.".yellow
            stdout <<< "To start a simulator: xsim start <device>".dim
        } else if showAvailableOnly {
            stdout <<< "No available simulators.".yellow
            stdout <<< "To create a simulator: xsim create <name> <type> <runtime>".dim
        } else {
            stdout <<< "No simulators found.".yellow
            stdout <<< "To create a simulator: xsim create <name> <type> <runtime>".dim
        }
    }

    /// Displays devices in a formatted table
    private func displayDevices(_ devices: [SimulatorDevice], runtimeNameById: [String: String], deviceTypeNameById: [String: String]) {
        // Group devices by runtime for better organization
        let groupedDevices = Dictionary(grouping: devices) { device in
            runtimeNameById[device.runtimeIdentifier] ?? extractRuntimeDisplayName(from: device.runtimeIdentifier)
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
                displayDeviceRow(device, deviceTypeNameById: deviceTypeNameById)
            }
        }

        // Display summary
        displaySummary(devices)
    }

    /// Displays the table header
    private func displayTableHeader() {
        let header =
            pad(truncateString("Name", maxLength: 25), to: 25) + " " +
            pad(truncateString("State", maxLength: 8), to: 8) + " " +
            pad(truncateString("Device Type", maxLength: 20), to: 20) + " " +
            "UUID"
        stdout <<< header.bold
        stdout <<< String(repeating: "-", count: 80).dim
    }

    /// Displays a single device row
    private func displayDeviceRow(_ device: SimulatorDevice, deviceTypeNameById: [String: String]) {
        let resolvedTypeName = deviceTypeNameById[device.deviceTypeIdentifier] ?? extractDeviceTypeName(from: device.deviceTypeIdentifier)
        let stateDisplay = formatDeviceState(device.state, isAvailable: device.isAvailable)

        let nameCol = pad(truncateString(device.name, maxLength: 25), to: 25)
        let stateCol = pad(truncateString(stateDisplay, maxLength: 8), to: 8)
        let typeCol = pad(truncateString(resolvedTypeName, maxLength: 20), to: 20)
        stdout <<< "\(nameCol) \(stateCol) \(typeCol) \(device.udid.dim)"
    }

    /// Formats the device state with appropriate colors
    private func formatDeviceState(_ state: SimulatorState, isAvailable: Bool) -> String {
        if !isAvailable {
            return "Unavailable".red
        }

        switch state {
        case .booted:
            return "Booted".green
        case .booting:
            return "Booting".yellow
        case .shutdown:
            return "Shutdown".dim
        case .shuttingDown:
            return "Shutting down".yellow
        }
    }

    /// Displays a summary of the devices
    private func displaySummary(_ devices: [SimulatorDevice]) {
        stdout <<< ""

        let totalCount = devices.count
        let runningCount = devices.count(where: { $0.state.isRunning })
        let availableCount = devices.count(where: { $0.isAvailable })

        stdout <<< "Total: \(totalCount), Running: \(runningCount), Available: \(availableCount)".dim

        if runningCount == 0, !showRunningOnly {
            stdout <<< ""
            stdout <<< "Tip: Use 'xsim start <device>' to boot a simulator".dim
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

    /// Pads a string with spaces on the right to the specified width
    private func pad(_ string: String, to width: Int) -> String {
        let count = string.count
        if count >= width { return string }
        return string + String(repeating: " ", count: width - count)
    }
}
