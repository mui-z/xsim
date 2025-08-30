import Foundation

enum Filters {
    /// Flexible runtime matching used in multiple commands.
    /// Accepts full identifier, display form (e.g., "iOS 26.0"), prefix like "iOS 17",
    /// or version-only like "17" / "17.0".
    static func runtimeMatches(filter: String, runtimeIdentifier: String) -> Bool {
        let filterLower = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if filterLower.isEmpty { return true }

        // Exact match against identifier
        if runtimeIdentifier.lowercased() == filterLower { return true }

        // Display name
        let display = DisplayFormat.runtimeName(from: runtimeIdentifier).lowercased()
        if display == filterLower { return true }

        // Prefix match like "iOS 17"
        if display.hasPrefix(filterLower) { return true }

        // Version-only match
        let versionOnly = display
            .replacingOccurrences(of: "ios ", with: "")
            .replacingOccurrences(of: "watchos ", with: "")
            .replacingOccurrences(of: "tvos ", with: "")
        if versionOnly == filterLower || versionOnly.hasPrefix(filterLower) { return true }

        return false
    }
}
