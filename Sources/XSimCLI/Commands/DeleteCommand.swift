import Rainbow
import SwiftCLI

/// Command to delete a simulator device
class DeleteCommand: BaseSimCommand, Command {
    let name = "delete"
    let shortDescription = "Delete a simulator"
    let longDescription = """
    Deletes the specified simulator device.
    If the simulator is running, it will be stopped before deletion.
    This action cannot be undone.

    You can also delete all simulators for a given OS/runtime version using --runtime.

    Examples:
      xsim delete "iPhone 15"                  # by name
      xsim delete 12345678-1234-1234-1234-123456789012  # by UUID
      xsim delete --runtime "iOS 17.0"         # all iOS 17.0 simulators
      xsim delete --runtime com.apple.CoreSimulator.SimRuntime.iOS-17-0
    """

    @Param var deviceIdentifier: String?

    @Flag("-f", "--force", description: "Delete without confirmation")
    var force: Bool

    @Key(
        "--runtime",
        description: "Delete all simulators for the specified runtime (e.g. 'iOS 17.0' or 'com.apple.CoreSimulator.SimRuntime.iOS-17-0')",
    )
    var runtimeFilter: String?

    override init() {}

    func execute() throws {
        do {
            let simulatorService = try getService()

            if let runtimeFilter, runtimeFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                // Bulk delete by runtime
                try deleteAllForRuntime(simulatorService: simulatorService, runtimeFilter: runtimeFilter)
            } else if let identifier = deviceIdentifier {
                // Single device delete
                let devices = try simulatorService.listDevices()
                guard let device = findDevice(in: devices, identifier: identifier) else {
                    throw SimulatorError.deviceNotFound(identifier)
                }

                // Show warning and device info
                displayDeleteWarning(device: device)

                // Confirm the delete operation unless forced
                if !force, !confirmDelete(device: device) {
                    stdout <<< "Delete operation cancelled".yellow
                    return
                }

                stdout <<< "Deleting simulator...".dim

                // 安全のため、確認時に表示したデバイスのUDIDで確実に削除する
                try simulatorService.deleteSimulator(identifier: device.udid)
                displayDeleteSuccess(device: device)
            } else {
                // No identifier or runtime specified
                stdout <<< "Error: Provide a device name/UUID or use --runtime to delete by OS version".red
                stdout <<< ""
                stdout <<< "Usage:".bold
                stdout <<< "  xsim delete <device>                # by name or UUID"
                stdout <<< "  xsim delete --runtime 'iOS 17.0'    # delete all for a runtime"
                stdout <<< "  xsim delete --runtime com.apple.CoreSimulator.SimRuntime.iOS-17-0".dim
                throw CLI.Error(message: "")
            }

        } catch let error as SimulatorError {
            try handleSimulatorError(error)
        } catch {
            throw CLI.Error(message: "An unexpected error occurred: \(error.localizedDescription)")
        }
    }

    /// Deletes all simulators that match the given runtime filter
    private func deleteAllForRuntime(simulatorService: SimulatorService, runtimeFilter: String) throws {
        let devices = try simulatorService.listDevices()

        let matchingDevices = devices.filter { device in
            Filters.runtimeMatches(filter: runtimeFilter, runtimeIdentifier: device.runtimeIdentifier)
        }

        if matchingDevices.isEmpty {
            stdout <<< "No simulators found for runtime filter: \(runtimeFilter)".yellow
            return
        }

        // Show a summary and confirm
        displayBulkDeleteWarning(devices: matchingDevices, runtimeFilter: runtimeFilter)
        if !force, !confirmBulkDelete(count: matchingDevices.count) {
            stdout <<< "Delete operation cancelled".yellow
            return
        }

        stdout <<< "Deleting \(matchingDevices.count) simulator(s) for runtime filter '\(runtimeFilter)'...".dim

        // Use bulk deletion for speed
        let udids = matchingDevices.map(\.udid)
        do {
            try simulatorService.deleteSimulators(udids: udids)
            stdout <<< "✓ Bulk delete completed".green
        } catch {
            // If bulk delete fails, fall back to per-device deletion with messages
            stdout <<< "Bulk delete failed, falling back to per-device: \(error.localizedDescription)".yellow
            for device in matchingDevices {
                do {
                    try simulatorService.deleteSimulator(identifier: device.udid)
                    stdout <<< "  ✓ Deleted: \(device.name) (\(DisplayFormat.deviceTypeName(from: device.deviceTypeIdentifier)))".green
                } catch {
                    stdout <<< "  ✗ Failed: \(device.name) - \(error.localizedDescription)".red
                }
            }
        }
    }

    // runtime matching is provided by Filters.runtimeMatches

    /// Displays a warning summary for bulk deletion
    private func displayBulkDeleteWarning(devices: [SimulatorDevice], runtimeFilter: String) {
        if force { return }
        stdout <<< "⚠️  Confirm bulk deletion".yellow.bold
        stdout <<< ""
        stdout <<< "The following \(devices.count) simulator(s) will be deleted for runtime filter '\(runtimeFilter)':".bold
        for device in devices.sorted(by: { $0.name < $1.name }) {
            let deviceTypeName = DisplayFormat.deviceTypeName(from: device.deviceTypeIdentifier)
            let runtimeName = DisplayFormat.runtimeName(from: device.runtimeIdentifier)
            stdout <<< "  • \(device.name) (\(deviceTypeName), \(runtimeName)) \(device.udid.dim)"
        }
        stdout <<< ""
        stdout <<< "This action cannot be undone.".red.bold
    }

    /// Confirms bulk deletion
    private func confirmBulkDelete(count: Int) -> Bool {
        stdout <<< "Proceed to delete \(count) simulator(s)? (y/N): ".bold
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return input == "y" || input == "yes"
    }

    /// Displays warning message before deletion
    private func displayDeleteWarning(device: SimulatorDevice) {
        if force {
            return // Skip warning if forced
        }

        stdout <<< "⚠️  Confirm deletion".yellow.bold
        stdout <<< ""

        let deviceTypeName = DisplayFormat.deviceTypeName(from: device.deviceTypeIdentifier)
        let runtimeName = DisplayFormat.runtimeName(from: device.runtimeIdentifier)

        stdout <<< "The following simulator will be deleted:".bold
        stdout <<< "  Name: \(device.name)"
        stdout <<< "  Type: \(deviceTypeName)"
        stdout <<< "  Runtime: \(runtimeName)"
        stdout <<< "  UUID: \(device.udid)".dim

        if device.state.isRunning {
            stdout <<< "  Current state: \(DisplayFormat.coloredState(device.state))"
            stdout <<< ""
            stdout <<< "Note: Running simulators will be stopped automatically".yellow
        }

        stdout <<< ""
        stdout <<< "This operation will delete:".red
        stdout <<< "  • The simulator device"
        stdout <<< "  • All apps and data"
        stdout <<< "  • System settings"
        stdout <<< "  • Log files"
        stdout <<< ""
        stdout <<< "This action cannot be undone.".red.bold
    }

    /// Confirms the delete operation with user
    private func confirmDelete(device _: SimulatorDevice) -> Bool {
        stdout <<< "Are you sure you want to delete? (y/N): ".bold

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }

        return input == "y" || input == "yes"
    }

    /// Handles specific simulator errors with helpful messages
    private func handleSimulatorError(_ error: SimulatorError) throws {
        switch error {
        case let .deviceNotFound(identifier):
            stdout <<< "✗ Device '\(identifier)' not found".red
            stdout <<< ""
            stdout <<< "To list available devices:".dim
            stdout <<< "  xsim list".cyan
            throw CLI.Error(message: "")

        default:
            throw CLI.Error(message: error.localizedDescription)
        }
    }

    /// Displays success message after deletion
    private func displayDeleteSuccess(device: SimulatorDevice) {
        stdout <<< "✓ Deleted the simulator".green
        stdout <<< ""

        let deviceTypeName = DisplayFormat.deviceTypeName(from: device.deviceTypeIdentifier)
        let runtimeName = DisplayFormat.runtimeName(from: device.runtimeIdentifier)

        stdout <<< "Deleted simulator:".bold
        stdout <<< "  Name: \(device.name)".dim
        stdout <<< "  Type: \(deviceTypeName)".dim
        stdout <<< "  Runtime: \(runtimeName)".dim
        stdout <<< "  UUID: \(device.udid)".dim

        stdout <<< ""
        stdout <<< "Tips:".dim
        stdout <<< "  • List remaining simulators: xsim list".dim
        stdout <<< "  • Create a new simulator: xsim create <name> <type> <runtime>".dim

        // Show available device types and runtimes for convenience
        stdout <<< "  • Available device types: xsim create --list-types".dim
        stdout <<< "  • Available runtimes: xsim create --list-runtimes".dim
    }
}

// Formatting and device resolution helpers are provided by BaseSimCommand and DisplayFormat
