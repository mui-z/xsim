import Foundation

/// Represents an application installed inside a simulator device
public struct SimulatorApp: Equatable {
    public enum ApplicationType: String {
        case user = "User"
        case system = "System"
        case unknown

        init(rawValue: String?) {
            guard let rawValue else {
                self = .unknown
                return
            }
            self = ApplicationType(rawValue: rawValue) ?? .unknown
        }

        /// Returns true when the app is considered a user-installed application.
        public var isUserApp: Bool {
            switch self {
            case .user:
                true
            case .system, .unknown:
                false
            }
        }
    }

    /// Bundle identifier for the application
    public let bundleIdentifier: String

    /// Display name resolved from the bundle (if available)
    public let name: String?

    /// Version string, derived from either CFBundleShortVersionString or CFBundleVersion
    public let version: String?

    /// Application type reported by simctl (System/User)
    public let applicationType: ApplicationType

    public init(bundleIdentifier: String, name: String?, version: String?, applicationType: ApplicationType) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.version = version
        self.applicationType = applicationType
    }

    /// Convenience accessor prioritising the display name when available.
    public var displayName: String { name ?? bundleIdentifier }
}
