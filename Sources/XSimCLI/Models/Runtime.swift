import Foundation

/// Represents a runtime available for simulator creation
public struct Runtime: Codable, Equatable {
    /// Unique identifier for the runtime
    public let identifier: String

    /// Human-readable name of the runtime
    public let name: String

    /// Version string of the runtime
    public let version: String

    /// Whether the runtime is available for use
    public let isAvailable: Bool

    public init(identifier: String, name: String, version: String, isAvailable: Bool) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.isAvailable = isAvailable
    }
}

public extension Runtime {
    /// Returns a display-friendly version of the runtime name
    var displayName: String {
        "\(name) (\(version))"
    }

    /// Returns true if this is an iOS runtime
    var isiOS: Bool {
        identifier.contains("iOS") || name.contains("iOS")
    }

    /// Returns true if this is a watchOS runtime
    var isWatchOS: Bool {
        identifier.contains("watchOS") || name.contains("watchOS")
    }

    /// Returns true if this is a tvOS runtime
    var isTvOS: Bool {
        identifier.contains("tvOS") || name.contains("tvOS")
    }

    /// Returns the major version number if available
    var majorVersion: Int? {
        let components = version.components(separatedBy: ".")
        return components.first.flatMap(Int.init)
    }
}
