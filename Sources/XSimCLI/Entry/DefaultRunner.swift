import Foundation

/// Entrypoint helper for default invocation behavior.
/// Public so the `XSim` executable target can invoke without importing internal types.
public enum DefaultRunner {
    /// If no args are provided and no simulators are running, attempts to start the last used simulator.
    /// - Returns: true if it handled the invocation (and started a simulator), false to continue normal CLI.
    public static func runIfNoArgs() -> Bool {
        let args = CommandLine.arguments
        guard args.count == 1 else { return false }

        do {
            let service = try SimulatorService()
            let devices = try service.listDevices()
            let running = devices.filter(\.state.isRunning)
            guard running.isEmpty else { return false }

            guard let lastUDID = RecentDeviceStore.lastBootedUDID() else { return false }
            if let dev = devices.first(where: { $0.udid == lastUDID }) {
                let typeName = DisplayFormat.deviceTypeName(from: dev.deviceTypeIdentifier)
                let runtimeName = DisplayFormat.runtimeName(from: dev.runtimeIdentifier)
                let line = "Starting last used simulator: \(dev.name) (\(typeName), \(runtimeName))\n"
                if let data = line.data(using: .utf8) { FileHandle.standardError.write(data) }
            } else {
                fputs("Starting last used simulator...\n", stderr)
            }
            try service.startSimulator(identifier: lastUDID)
            return true
        } catch {
            // Best-effort only; fall back to normal CLI
            Env.debug("DefaultRunner skipped due to error: \(error.localizedDescription)")
            return false
        }
    }
}
