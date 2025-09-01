import Foundation

/// Persists and resolves the most recently booted simulator device.
///
/// - Stores the last booted UDID under `~/.xsim/state.json`.
/// - Provides a read API used by default-run behavior.
enum RecentDeviceStore {
    private struct State: Codable {
        let lastBootedUDID: String
        let updatedAt: Date
    }

    private static var stateFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".xsim", isDirectory: true)
        return dir.appendingPathComponent("state.json", isDirectory: false)
    }

    /// Saves the last booted UDID and timestamp.
    static func recordLastBooted(udid: String) {
        do {
            let url = stateFileURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let payload = State(lastBootedUDID: udid, updatedAt: Date())
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: .atomic)
        } catch {
            // Best-effort; avoid throwing to not break main flows
            Env.debug("Failed to record lastBootedUDID: \(error.localizedDescription)")
        }
    }

    /// Returns the last booted UDID recorded by this tool, if any.
    static func lastBootedUDID() -> String? {
        do {
            let url = stateFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            let state = try JSONDecoder().decode(State.self, from: data)
            return state.lastBootedUDID
        } catch {
            Env.debug("Failed to load lastBootedUDID: \(error.localizedDescription)")
            return nil
        }
    }
}
