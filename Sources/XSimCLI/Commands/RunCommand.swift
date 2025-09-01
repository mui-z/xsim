import Rainbow
import SwiftCLI

/// Command to run a simulator.
///
/// Behavior:
/// - With an argument, starts the specified simulator (same as `start`).
/// - Without an argument, if no simulators are running, starts the most recently used one.
class RunCommand: BaseSimCommand, Command {
    let name = "run"
    let shortDescription = "Run a simulator (default)"
    let longDescription = """
    Runs a simulator.
    If no device is specified and no simulators are currently running, it starts the most recently used simulator.

    Examples:
      xsim run                          # start last used (if none running)
      xsim run "iPhone 15"               # start a specific device
      xsim run 12345678-1234-1234-1234-123456789012  # by UUID
    """

    @Param var deviceIdentifier: String?

    override init() {}

    func execute() throws {
        do {
            let simulatorService = try getService()

            if let identifier = deviceIdentifier {
                stdout <<< "Starting simulator...".dim
                try simulatorService.startSimulator(identifier: identifier)
                try displayStartedDeviceInfo(for: identifier, service: simulatorService)
                return
            }

            // No identifier given; start last used only when nothing is running
            let devices = try simulatorService.listDevices()
            let running = devices.filter(\.state.isRunning)
            if !running.isEmpty {
                stdout <<< "Simulators already running (\(running.count)). Use 'xsim list --running' to view.".yellow
                return
            }

            if let lastUDID = RecentDeviceStore.lastBootedUDID() {
                stdout <<< "Starting last used simulator...".dim
                try simulatorService.startSimulator(identifier: lastUDID)
                try displayStartedDeviceInfo(for: lastUDID, service: simulatorService)
            } else {
                stdout <<< "No recent simulator recorded.".yellow
                stdout <<< "Specify a device: xsim start <name|UUID> or list: xsim list".dim
            }

        } catch let error as SimulatorError {
            throw CLI.Error(message: error.localizedDescription)
        } catch {
            throw CLI.Error(message: "An unexpected error occurred: \(error.localizedDescription)")
        }
    }

    private func displayStartedDeviceInfo(for identifier: String, service: SimulatorService) throws {
        let devices = try service.listDevices()
        if let device = findDevice(in: devices, identifier: identifier) ?? devices.first(where: { $0.udid == identifier }) {
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
        }
    }
}
