import Foundation

/// Represents a device type available for simulator creation
public struct DeviceType: Codable, Equatable {
    /// Unique identifier for the device type
    public let identifier: String

    /// Human-readable name of the device type
    public let name: String

    public init(identifier: String, name: String) {
        self.identifier = identifier
        self.name = name
    }
}

public extension DeviceType {
    /// Returns a display-friendly version of the device type name
    var displayName: String {
        // Remove common prefixes to make names more readable
        name
            .replacingOccurrences(of: "iPhone ", with: "iPhone ")
            .replacingOccurrences(of: "iPad ", with: "iPad ")
            .replacingOccurrences(of: "Apple ", with: "")
    }

    /// Returns true if this is an iPhone device type
    var isiPhone: Bool {
        name.contains("iPhone")
    }

    /// Returns true if this is an iPad device type
    var isiPad: Bool {
        name.contains("iPad")
    }

    /// Returns true if this is an Apple Watch device type
    var isWatch: Bool {
        name.contains("Watch")
    }

    /// Returns true if this is an Apple TV device type
    var isTV: Bool {
        name.contains("TV")
    }
}
