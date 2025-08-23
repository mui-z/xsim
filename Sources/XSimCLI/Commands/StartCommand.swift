import Rainbow
import SwiftCLI

/// Command to start a simulator device
class StartCommand: Command {
    let name = "start"
    let shortDescription = "Start a simulator"
    let longDescription = """
    Starts the specified simulator device.
    You can specify the device by name or UUID.

    Examples:
      xsim start "iPhone 15"                    # by name
      xsim start 12345678-1234-1234-1234-123456789012  # by UUID
    """

    @Param var deviceIdentifier: String

    private var simulatorService: SimulatorService?

    init() {}

    func execute() throws {
        do {
            stdout <<< "Starting simulator...".dim

            // Start the simulator
            let simulatorService = try getService()
            try simulatorService.startSimulator(identifier: deviceIdentifier)

            // Get device info for confirmation
            let devices = try simulatorService.listDevices()
            if let device = findDevice(devices: devices, identifier: deviceIdentifier) {
                displayStartSuccess(device: device)
            } else {
                stdout <<< "✓ Started simulator '\(deviceIdentifier)'".green
            }

        } catch let error as SimulatorError {
            try handleSimulatorError(error)
        } catch {
            throw CLI.Error(message: "An unexpected error occurred: \(error.localizedDescription)")
        }
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

        case let .deviceAlreadyRunning(identifier):
            stdout <<< "ℹ Device '\(identifier)' is already running".yellow

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
        stdout <<< "✓ Simulator started".green
        stdout <<< ""

        let deviceTypeName = extractDeviceTypeName(from: device.deviceTypeIdentifier)
        let runtimeName = extractRuntimeDisplayName(from: device.runtimeIdentifier)

        stdout <<< "Device Information:".bold
        stdout <<< "  Name: \(device.name)".dim
        stdout <<< "  Type: \(deviceTypeName)".dim
        stdout <<< "  Runtime: \(runtimeName)".dim
        stdout <<< "  UUID: \(device.udid)".dim
        stdout <<< "  State: \(formatDeviceState(device.state))".dim

        if device.state == .booting {
            stdout <<< ""
            stdout <<< "Tip: Please wait for the simulator to finish booting.".dim
        }
    }

    /// Displays current device status
    private func displayDeviceStatus(device: SimulatorDevice) {
        stdout <<< ""
        stdout <<< "Current Status:".dim
        stdout <<< "  Name: \(device.name)"
        stdout <<< "  State: \(formatDeviceState(device.state))"
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
