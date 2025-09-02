import Foundation

/// Entrypoint helper for default invocation behavior.
/// Public so the `XSim` executable target can invoke without importing internal types.
public enum DefaultRunner {
    /// If no args are provided, execute the same behavior as `xsim boot` with no arguments.
    /// - Returns: true if it handled the invocation, false to continue normal CLI.
    public static func runIfNoArgs() -> Bool {
        let args = CommandLine.arguments
        guard args.count == 1 else { return false }

        // Delegate to BootCommand for a single source of truth on default behavior.
        // Any messages or error handling are performed by the command itself.
        do {
            let cmd = BootCommand()
            try cmd.execute()
        } catch {
            // Swallow, since BootCommand has already surfaced messages appropriately.
        }
        return true
    }
}
