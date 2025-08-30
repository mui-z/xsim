import Rainbow
import SwiftCLI

/// Command to diagnose environment
class DoctorCommand: BaseSimCommand, Command {
    let name = "doctor"
    let shortDescription = "Check environment and simctl support"
    let longDescription = """
    Runs a series of checks to verify your environment can run xsim.
    Verifies xcrun path, simctl availability, and JSON output support.
    """

    override init() {}

    func execute() throws {
        do {
            let service = try getService()
            let report = try service.diagnoseEnvironment()

            stdout <<< "Environment Doctor".bold.blue
            stdout <<< ""
            stdout <<< "xcrun: \(report.xcrunPath)".dim
            stdout <<< (report.simctlAvailable ? "✓ simctl available".green : "✗ simctl unavailable".red)
            stdout <<< (report.jsonSupported ? "✓ JSON supported (list)".green : "✗ JSON not supported (list)".red)

            if !report.notes.isEmpty {
                stdout <<< ""
                stdout <<< "Notes:".bold
                for n in report.notes {
                    stdout <<< "  • \(n)".dim
                }
            }
        } catch let error as SimulatorError {
            throw CLI.Error(message: error.localizedDescription)
        } catch {
            throw CLI.Error(message: "An unexpected error occurred: \(error.localizedDescription)")
        }
    }
}
