import Rainbow
import SwiftCLI

/// Command to start a simulator device
class StartCommand: BaseSimCommand, Command {
    let name = "start"
    let shortDescription = "Start a simulator"
    let longDescription = """
    Starts the specified simulator device.
    You can specify the device by name or UUID.

    Examples:
      xsim start "iPhone 15"                    # by name
      xsim start 12345678-1234-1234-1234-123456789012  # by UUID
      xsim start "iPhone 15" --runtime iOS 17     # disambiguate by runtime
    """

    @Param var deviceIdentifier: String

    @Key("--runtime", description: "Filter by runtime when selecting by name (e.g. 'iOS 17', '17.0' or a runtime identifier)")
    var runtimeFilter: String?

    override init() {}

    func execute() throws {
        do {
            stdout <<< "Starting simulator...".dim

            // Start the simulator
            let simulatorService = try getService()
            try simulatorService.startSimulator(identifier: deviceIdentifier, runtimeFilter: runtimeFilter)

            // Get device info for confirmation
            let devices = try simulatorService.listDevices()
            if let device = findDevice(in: devices, identifier: deviceIdentifier) {
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

    /// Displays success message with device information
    private func displayStartSuccess(device: SimulatorDevice) {
        stdout <<< "✓ Simulator started".green
        stdout <<< ""

        let deviceTypeName = DisplayFormat.deviceTypeName(from: device.deviceTypeIdentifier)
        let runtimeName = DisplayFormat.runtimeName(from: device.runtimeIdentifier)

        stdout <<< "Device Information:".bold
        stdout <<< "  Name: \(device.name)".dim
        stdout <<< "  Type: \(deviceTypeName)".dim
        stdout <<< "  Runtime: \(runtimeName)".dim
        stdout <<< "  UUID: \(device.udid)".dim
        stdout <<< "  State: \(DisplayFormat.coloredState(device.state))".dim

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
        stdout <<< "  State: \(DisplayFormat.coloredState(device.state))"
        stdout <<< "  UUID: \(device.udid)".dim
    }

    // Formatting helpers moved to DisplayFormat and BaseSimCommand
}
