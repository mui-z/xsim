import Rainbow
import SwiftCLI

/// Command to boot a simulator device
class BootCommand: BaseSimCommand, Command {
    var name: String { "boot" }
    var shortDescription: String { "Boot a simulator" }
    let longDescription = """
    Boots the specified simulator device.
    You can specify the device by name or UUID.
    If no device is specified and no simulators are running, boots the most recently used simulator.

    Examples:
      xsim boot                                # boot last used (if none running)
      xsim boot "iPhone 16"                    # by name
      xsim boot 12345678-1234-1234-1234-123456789012  # by UUID
      xsim boot "iPhone 16" --runtime "iOS 26"   # disambiguate by runtime
    """

    @Param var deviceIdentifier: String?

    @Key("--runtime", description: "Filter by runtime when selecting by name (e.g. 'iOS 17', '17.0' or a runtime identifier)")
    var runtimeFilter: String?

    override init() {}

    func execute() throws {
        do {
            let simulatorService = try getService()

            if let identifier = deviceIdentifier {
                stdout <<< "Booting simulator...".dim
                // Boot the specified simulator
                try simulatorService.startSimulator(identifier: identifier, runtimeFilter: runtimeFilter)

                // Get device info for confirmation
                let devices = try simulatorService.listDevices()
                if let device = findDevice(in: devices, identifier: identifier) {
                    displayStartSuccess(device: device)
                } else {
                    stdout <<< "✓ Booted simulator '\(identifier)'".green
                }
            } else {
                // No identifier specified: if nothing is running, boot the most recently used simulator
                let devices = try simulatorService.listDevices()
                let running = devices.filter(\.state.isRunning)
                if !running.isEmpty {
                    stdout <<< "Simulators already running (\(running.count)). Use 'xsim list --running' to view.".yellow
                    return
                }

                if let lastUDID = RecentDeviceStore.lastBootedUDID() {
                    if let dev = devices.first(where: { $0.udid == lastUDID }) {
                        let typeName = DisplayFormat.deviceTypeName(from: dev.deviceTypeIdentifier)
                        let runtimeName = DisplayFormat.runtimeName(from: dev.runtimeIdentifier)
                        stdout <<< "Booting last used simulator: \(dev.name) (\(typeName), \(runtimeName))".dim
                    } else {
                        stdout <<< "Booting last used simulator...".dim
                    }
                    try simulatorService.startSimulator(identifier: lastUDID)
                    // Show info after boot
                    let updated = try simulatorService.listDevices()
                    if let device = updated.first(where: { $0.udid == lastUDID }) {
                        displayStartSuccess(device: device)
                    } else {
                        stdout <<< "✓ Simulator booted".green
                    }
                } else {
                    stdout <<< "No recent simulator recorded.".yellow
                    stdout <<< "Specify a device: xsim boot <name|UUID> or list: xsim list".dim
                }
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
            if let rf = runtimeFilter?.trimmingCharacters(in: .whitespacesAndNewlines), !rf.isEmpty {
                stdout <<< "✗ Device '\(identifier)' not found for runtime '\(rf)'".red
                stdout <<< ""
                stdout <<< "Try filtering by runtime:".dim
                stdout <<< "  xsim list --runtime \"\(rf)\" --name-contains \"\(identifier)\"".cyan
            } else {
                stdout <<< "✗ Device '\(identifier)' not found".red
                stdout <<< ""
                stdout <<< "To list available devices:".dim
                stdout <<< "  xsim list".cyan
            }
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
        stdout <<< "✓ Simulator booted".green
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
