import Rainbow
import SwiftCLI

/// Command to reset (erase) a simulator device
class ResetCommand: Command {
    let name = "reset"
    let shortDescription = "Reset a simulator"
    let longDescription = """
    Erases all data and settings of the specified simulator device.
    The simulator returns to its initial state after reset.
    Running simulators will be stopped automatically before reset.

    Examples:
      xsim reset "iPhone 15"                   # by name
      xsim reset 12345678-1234-1234-1234-123456789012  # by UUID
    """

    @Param var deviceIdentifier: String

    private var simulatorService: SimulatorService?

    init() {}

    func execute() throws {
        do {
            // Get device info before resetting
            let simulatorService = try getService()
            let devices = try simulatorService.listDevices()
            guard let device = findDevice(devices: devices, identifier: deviceIdentifier) else {
                throw SimulatorError.deviceNotFound(deviceIdentifier)
            }

            // Show warning and device info
            displayResetWarning(device: device)

            // Confirm the reset operation
            if !confirmReset(device: device) {
                stdout <<< "Reset operation cancelled".yellow
                return
            }

            stdout <<< "Resetting simulator...".dim

            // Reset the device
            try simulatorService.resetSimulator(identifier: deviceIdentifier)

            displayResetSuccess(device: device)

        } catch let error as SimulatorError {
            try handleSimulatorError(error)
        } catch {
            throw CLI.Error(message: "An unexpected error occurred: \(error.localizedDescription)")
        }
    }

    /// Displays warning message before reset
    private func displayResetWarning(device: SimulatorDevice) {
        stdout <<< "⚠️  Confirm reset".yellow.bold
        stdout <<< ""

        let deviceTypeName = extractDeviceTypeName(from: device.deviceTypeIdentifier)
        let runtimeName = extractRuntimeDisplayName(from: device.runtimeIdentifier)

        stdout <<< "The following simulator will be reset:".bold
        stdout <<< "  Name: \(device.name)"
        stdout <<< "  Type: \(deviceTypeName)"
        stdout <<< "  Runtime: \(runtimeName)"
        stdout <<< "  UUID: \(device.udid)".dim

        if device.state.isRunning {
            stdout <<< "  Current state: \(formatDeviceState(device.state))"
            stdout <<< ""
            stdout <<< "Note: Running simulators will be stopped automatically".yellow
        }

        stdout <<< ""
        stdout <<< "This operation will delete:".red
        stdout <<< "  • All apps and data"
        stdout <<< "  • System settings"
        stdout <<< "  • Keychain data"
        stdout <<< "  • Log files"
        stdout <<< ""
        stdout <<< "This action cannot be undone.".red.bold
    }

    /// Confirms the reset operation with user
    private func confirmReset(device _: SimulatorDevice) -> Bool {
        stdout <<< "Are you sure you want to reset? (y/N): ".bold

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

    /// Displays success message after reset
    private func displayResetSuccess(device: SimulatorDevice) {
        stdout <<< "✓ Reset completed".green
        stdout <<< ""

        let deviceTypeName = extractDeviceTypeName(from: device.deviceTypeIdentifier)
        let runtimeName = extractRuntimeDisplayName(from: device.runtimeIdentifier)

        stdout <<< "Reset details:".bold
        stdout <<< "  Name: \(device.name)".dim
        stdout <<< "  Type: \(deviceTypeName)".dim
        stdout <<< "  Runtime: \(runtimeName)".dim
        stdout <<< "  UUID: \(device.udid)".dim
        stdout <<< ""
        stdout <<< "The simulator has been returned to its initial state.".green
        stdout <<< ""
        stdout <<< "Tips:".dim
        stdout <<< "  • To start the simulator: xsim start \"\(device.name)\"".dim
        stdout <<< "  • To list other simulators: xsim list".dim
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
            "Booted".green
        case .booting:
            "Booting".yellow
        case .shutdown:
            "Shutdown".dim
        case .shuttingDown:
            "Shutting down".yellow
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
extension ResetCommand {
    private func getService() throws -> SimulatorService {
        if let service = simulatorService { return service }
        let service = try SimulatorService()
        simulatorService = service
        return service
    }
}
