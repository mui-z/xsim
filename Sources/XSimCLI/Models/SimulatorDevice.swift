import Foundation

/// Represents a simulator device with its properties and state
public struct SimulatorDevice: Codable, Equatable {
    /// Unique device identifier
    public let udid: String

    /// Human-readable device name
    public let name: String

    /// Current state of the simulator
    public let state: SimulatorState

    /// Device type identifier (e.g., "com.apple.CoreSimulator.SimDeviceType.iPhone-15")
    public let deviceTypeIdentifier: String

    /// Runtime identifier (e.g., "com.apple.CoreSimulator.SimRuntime.iOS-17-0")
    public let runtimeIdentifier: String

    /// Whether the device is available for use
    public let isAvailable: Bool

    public init(
        udid: String,
        name: String,
        state: SimulatorState,
        deviceTypeIdentifier: String,
        runtimeIdentifier: String,
        isAvailable: Bool,
    ) {
        self.udid = udid
        self.name = name
        self.state = state
        self.deviceTypeIdentifier = deviceTypeIdentifier
        self.runtimeIdentifier = runtimeIdentifier
        self.isAvailable = isAvailable
    }
}

/// Represents the possible states of a simulator device
public enum SimulatorState: String, CaseIterable, Codable {
    case shutdown = "Shutdown"
    case booted = "Booted"
    case booting = "Booting"
    case shuttingDown = "Shutting Down"

    /// Returns true if the simulator is currently running
    public var isRunning: Bool {
        switch self {
        case .booted, .booting:
            true
        case .shutdown, .shuttingDown:
            false
        }
    }

    /// Returns a localized display string for the state
    public var displayName: String {
        switch self {
        case .shutdown:
            "停止中"
        case .booted:
            "起動中"
        case .booting:
            "起動処理中"
        case .shuttingDown:
            "停止処理中"
        }
    }
}
