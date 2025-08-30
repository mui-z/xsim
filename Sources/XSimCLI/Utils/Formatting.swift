import Rainbow

enum DisplayFormat {
    // MARK: - Identifier -> Display Name

    static func runtimeName(from identifier: String) -> String {
        let components = identifier.components(separatedBy: ".")
        guard let lastComponent = components.last else { return identifier }

        if lastComponent.hasPrefix("iOS-") {
            let version = lastComponent
                .replacingOccurrences(of: "iOS-", with: "")
                .replacingOccurrences(of: "-", with: ".")
            return "iOS \(version)"
        } else if lastComponent.hasPrefix("watchOS-") {
            let version = lastComponent
                .replacingOccurrences(of: "watchOS-", with: "")
                .replacingOccurrences(of: "-", with: ".")
            return "watchOS \(version)"
        } else if lastComponent.hasPrefix("tvOS-") {
            let version = lastComponent
                .replacingOccurrences(of: "tvOS-", with: "")
                .replacingOccurrences(of: "-", with: ".")
            return "tvOS \(version)"
        }

        return lastComponent
    }

    static func deviceTypeName(from identifier: String) -> String {
        let components = identifier.components(separatedBy: ".")
        guard let lastComponent = components.last else { return identifier }
        return lastComponent.replacingOccurrences(of: "-", with: " ")
    }

    // MARK: - State Formatting

    static func coloredState(_ state: SimulatorState, isAvailable: Bool = true) -> String {
        if !isAvailable { return "Unavailable".red }
        switch state {
        case .booted:
            return "Booted".green
        case .booting:
            return "Booting".yellow
        case .shutdown:
            return "Shutdown".dim
        case .shuttingDown:
            return "Shutting down".yellow
        }
    }

    // MARK: - Column Utilities

    static func truncate(_ string: String, maxLength: Int) -> String {
        guard maxLength > 0 else { return "" }
        if string.count <= maxLength { return string }
        let truncated = String(string.prefix(maxLength - 3))
        return truncated + "..."
    }

    static func pad(_ string: String, to width: Int) -> String {
        let count = string.count
        if count >= width { return string }
        return string + String(repeating: " ", count: width - count)
    }
}
