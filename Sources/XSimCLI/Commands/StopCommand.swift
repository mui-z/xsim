import Rainbow
import SwiftCLI

/// Command to shut down simulator devices
class StopCommand: BaseSimCommand, Command {
    var name: String { "shutdown" }
    var shortDescription: String { "Shutdown simulators" }
    let longDescription = """
    Shuts down the specified simulator device.
    If no device is specified, shuts down all running simulators.

    Examples:
      xsim shutdown                             # shutdown all running simulators
      xsim shutdown "iPhone 15"                 # shutdown a specific device
      xsim shutdown 12345678-1234-1234-1234-123456789012  # by UUID
    """

    @Param var deviceIdentifier: String?

    override init() {}

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
        stdout <<< "Shutting down simulator...".dim

        // Get device info before stopping
        let simulatorService = try getService()
        let devices = try simulatorService.listDevices()
        guard let device = findDevice(in: devices, identifier: identifier) else {
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

        stdout <<< "Shutting down all running simulators...".dim

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
            stdout <<< "ℹ Device '\(identifier)' is already shut down".yellow

            // Try to get device info to show current status
            do {
                let simulatorService = try getService()
                let devices = try simulatorService.listDevices()
                if let device = findDevice(in: devices, identifier: identifier) {
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
        stdout <<< "✓ Shut down the simulator".green
        stdout <<< ""

        let deviceTypeName = DisplayFormat.deviceTypeName(from: device.deviceTypeIdentifier)
        let runtimeName = DisplayFormat.runtimeName(from: device.runtimeIdentifier)

        stdout <<< "Device Information:".bold
        stdout <<< "  Name: \(device.name)".dim
        stdout <<< "  Type: \(deviceTypeName)".dim
        stdout <<< "  Runtime: \(runtimeName)".dim
        stdout <<< "  UUID: \(device.udid)".dim
    }

    /// Displays success message for stopping all devices
    private func displayStopAllSuccess(stoppedDevices: [SimulatorDevice]) {
        stdout <<< "✓ Shut down all simulators".green
        stdout <<< ""

        stdout <<< "Stopped devices (\(stoppedDevices.count)):".bold
        for device in stoppedDevices.sorted(by: { $0.name < $1.name }) {
            let deviceTypeName = DisplayFormat.deviceTypeName(from: device.deviceTypeIdentifier)
            stdout <<< "  • \(device.name) (\(deviceTypeName))".dim
        }

        stdout <<< ""
        stdout <<< "Tip: Use 'xsim boot <device>' to boot a simulator again".dim
    }

    /// Displays current device status
    private func displayDeviceStatus(device: SimulatorDevice) {
        stdout <<< ""
        stdout <<< "Current Status:".dim
        stdout <<< "  Name: \(device.name)"
        stdout <<< "  State: \(DisplayFormat.coloredState(device.state))"
        stdout <<< "  UUID: \(device.udid)".dim
    }
}
