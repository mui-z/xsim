import Rainbow
import SwiftCLI

/// Command to list available simulator devices
class ListCommand: BaseSimCommand, Command {
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

    @Key("--runtime", description: "Filter by runtime (e.g. 'iOS 17', '17.0' or a runtime identifier)")
    var runtimeFilter: String?

    @Key("--name-contains", description: "Filter by device name substring (case-insensitive)")
    var nameContains: String?

    override init() {}

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

            // Debug
            Env.debug("Total devices fetched: \(devices.count). runningOnly=\(showRunningOnly), availableOnly=\(showAvailableOnly)")

            // Filter devices based on flags and runtime filter
            let filteredDevices = filterDevices(devices)
                .filter { device in
                    if let rf = runtimeFilter, !rf.isEmpty {
                        return Filters.runtimeMatches(filter: rf, runtimeIdentifier: device.runtimeIdentifier)
                    }
                    return true
                }
                .filter { device in
                    if let q = nameContains, !q.isEmpty {
                        return device.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    }
                    return true
                }

            if filteredDevices.isEmpty {
                // Debug
                Env.debug("No devices after filtering. Original=\(devices.count)")
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
            runtimeNameById[device.runtimeIdentifier] ?? DisplayFormat.runtimeName(from: device.runtimeIdentifier)
        }

        let sortedRuntimes = sortRuntimeKeys(Array(groupedDevices.keys), grouped: groupedDevices)

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

    /// Sort runtime headers: iOS -> watchOS -> tvOS -> other, version desc
    private func sortRuntimeKeys(_ keys: [String], grouped: [String: [SimulatorDevice]]) -> [String] {
        func platformOrder(_ identifier: String) -> Int {
            if identifier.contains(".SimRuntime.iOS-") { return 0 }
            if identifier.contains(".SimRuntime.watchOS-") { return 1 }
            if identifier.contains(".SimRuntime.tvOS-") { return 2 }
            return 3
        }

        func versionInts(from identifier: String) -> [Int] {
            // last component like iOS-17-0 / watchOS-10-2
            let parts = identifier.split(separator: ".")
            guard let last = parts.last else { return [] }
            var s = String(last)
            for p in ["iOS-", "watchOS-", "tvOS-"] {
                s = s.replacingOccurrences(of: p, with: "")
            }
            let dot = s.replacingOccurrences(of: "-", with: ".")
            return dot.split(separator: ".").compactMap { Int($0) }
        }

        func compareVersionsDesc(_ a: [Int], _ b: [Int]) -> Bool {
            let n = max(a.count, b.count)
            for i in 0 ..< n {
                let ai = i < a.count ? a[i] : 0
                let bi = i < b.count ? b[i] : 0
                if ai != bi { return ai > bi }
            }
            return false
        }

        return keys.sorted { lhs, rhs in
            guard
                let lId = grouped[lhs]?.first?.runtimeIdentifier,
                let rId = grouped[rhs]?.first?.runtimeIdentifier
            else { return lhs < rhs }

            let lp = platformOrder(lId)
            let rp = platformOrder(rId)
            if lp != rp { return lp < rp }

            let lv = versionInts(from: lId)
            let rv = versionInts(from: rId)
            if lv != rv { return compareVersionsDesc(lv, rv) }

            return lhs < rhs
        }
    }

    /// Displays the table header
    private func displayTableHeader() {
        let header =
            DisplayFormat.pad(DisplayFormat.truncate("Name", maxLength: 25), to: 25) + " " +
            DisplayFormat.pad(DisplayFormat.truncate("State", maxLength: 8), to: 8) + " " +
            DisplayFormat.pad(DisplayFormat.truncate("Device Type", maxLength: 20), to: 20) + " " +
            "UUID"
        stdout <<< header.bold
        stdout <<< String(repeating: "-", count: 80).dim
    }

    /// Displays a single device row
    private func displayDeviceRow(_ device: SimulatorDevice, deviceTypeNameById: [String: String]) {
        let resolvedTypeName = deviceTypeNameById[device.deviceTypeIdentifier] ?? DisplayFormat
            .deviceTypeName(from: device.deviceTypeIdentifier)
        let stateDisplay = DisplayFormat.coloredState(device.state, isAvailable: device.isAvailable)

        let nameCol = DisplayFormat.pad(DisplayFormat.truncate(device.name, maxLength: 25), to: 25)
        let stateCol = DisplayFormat.pad(DisplayFormat.truncate(stateDisplay, maxLength: 8), to: 8)
        let typeCol = DisplayFormat.pad(DisplayFormat.truncate(resolvedTypeName, maxLength: 20), to: 20)
        stdout <<< "\(nameCol) \(stateCol) \(typeCol) \(device.udid.dim)"
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

    // Identifier and column helpers moved to DisplayFormat
}
