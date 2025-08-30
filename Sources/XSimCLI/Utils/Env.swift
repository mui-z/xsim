import Foundation

enum Env {
    /// Whether verbose debug logging is enabled.
    /// Enable with: `XSIM_VERBOSE=1 xsim ...`
    static var verbose: Bool {
        let env = ProcessInfo.processInfo.environment
        if let v = env["XSIM_VERBOSE"]?.lowercased() {
            return v == "1" || v == "true" || v == "yes"
        }
        return false
    }

    /// Write a debug line to stderr when verbose is enabled.
    static func debug(_ message: String) {
        guard verbose else { return }
        let line = "Debug: \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
