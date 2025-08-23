import Rainbow
import SwiftCLI

/// Command to stop simulator devices
class StopCommand: Command {
    let name = "stop"
    let shortDescription = "Stop simulators"
    let longDescription = """
    Stops the specified simulator device.
    If no device is specified, stops all running simulators.

    Examples:
      xsim stop                                 # stop all running simulators
      xsim stop "iPhone 15"                     # stop a specific device
      xsim stop 12345678-1234-1234-1234-123456789012  # by UUID
    """

    @Param var deviceIdentifier: String?

    private var simulatorService: SimulatorService?

    init() {}

    func execute() throws {
        do {
            if let identifier = deviceIdentifier {
                // Stop specific device
                try stopSpecificDevice(identifier: identifier)
            } else {
                // Stop all running devices
                try stopAllDevices()
            }

        } catch let error as SimulatorError {
            try handleSimulatorError(error)
        } catch {
            throw CLI.Error(message: "An unexpected error occurred: \(error.localizedDescription)")
        }
    }

    /// Stops a specific device
    private func stopSpecificDevice(identifier: String) throws {
        stdout <<< "Stopping simulator...".dim

        // Get device info before stopping
        let simulatorService = try getService()
        let devices = try simulatorService.listDevices()
        guard let device = findDevice(devices: devices, identifier: identifier) else {
            throw SimulatorError.deviceNotFound(identifier)
        }

        // Stop the device
        try simulatorService.stopSimulator(identifier: identifier)

        displayStopSuccess(device: device)
    }

    /// Stops all running devices
    private func stopAllDevices() throws {
        // Get list of running devices before stopping
        let simulatorService = try getService()
        let devices = try simulatorService.listDevices()
        let runningDevices = devices.filter(\.state.isRunning)

        if runningDevices.isEmpty {
            stdout <<< "No simulators are running".yellow
            return
        }

        stdout <<< "Stopping all running simulators...".dim

        // Stop all devices
        try simulatorService.stopSimulator(identifier: nil)

        displayStopAllSuccess(stoppedDevices: runningDevices)
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

        case let .deviceNotRunning(identifier):
            stdout <<< "ℹ Device '\(identifier)' is already stopped".yellow

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

    /// Displays success message for stopping a specific device
    private func displayStopSuccess(device: SimulatorDevice) {
        stdout <<< "✓ Stopped the simulator".green
        stdout <<< ""

        let deviceTypeName = extractDeviceTypeName(from: device.deviceTypeIdentifier)
        let runtimeName = extractRuntimeDisplayName(from: device.runtimeIdentifier)

        stdout <<< "Device Information:".bold
        stdout <<< "  Name: \(device.name)".dim
        stdout <<< "  Type: \(deviceTypeName)".dim
        stdout <<< "  Runtime: \(runtimeName)".dim
        stdout <<< "  UUID: \(device.udid)".dim
    }

    /// Displays success message for stopping all devices
    private func displayStopAllSuccess(stoppedDevices: [SimulatorDevice]) {
        stdout <<< "✓ Stopped all simulators".green
        stdout <<< ""

        stdout <<< "Stopped devices (\(stoppedDevices.count)):".bold
        for device in stoppedDevices.sorted(by: { $0.name < $1.name }) {
            let deviceTypeName = extractDeviceTypeName(from: device.deviceTypeIdentifier)
            stdout <<< "  • \(device.name) (\(deviceTypeName))".dim
        }

        stdout <<< ""
        stdout <<< "Tip: Use 'xsim start <device>' to boot a simulator again".dim
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

// Lazy service accessor
extension StopCommand {
    private func getService() throws -> SimulatorService {
        if let service = simulatorService { return service }
        let service = try SimulatorService()
        simulatorService = service
        return service
    }
}
