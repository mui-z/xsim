import Dispatch
import Foundation

/// Service class for managing iOS Simulator operations through simctl
class SimulatorService {
    // MARK: - Private Properties

    private let xcrunPath: String

    // MARK: - Core simctl Execution Utilities

    /// Executes a simctl command and returns the output
    /// - Parameters:
    ///   - arguments: The simctl command arguments
    ///   - requiresJSON: Whether the command should return JSON output
    /// - Returns: The command output as Data
    /// - Throws: SimulatorError if the command fails
    private func executeSimctlCommand(arguments: [String], requiresJSON: Bool = false, timeoutSeconds: TimeInterval? = nil) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcrunPath)

        var fullArguments = ["simctl"]
        fullArguments.append(contentsOf: arguments)

        // Add JSON output flag if required.
        // simctl expects --json as an option to the 'list' subcommand, e.g.:
        //   xcrun simctl list --json devices
        // not before the subcommand. Place it right after 'list' when present.
        if requiresJSON, !arguments.contains("--json") {
            if let listIndex = fullArguments.firstIndex(of: "list") {
                fullArguments.insert("--json", at: listIndex + 1)
            } else {
                // Fallback: if 'list' isn't present for some reason, append at end
                fullArguments.append("--json")
            }
        }

        process.arguments = fullArguments

        // Debug
        Env.debug("Executing command: \(xcrunPath) \(fullArguments.joined(separator: " "))")

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Drain stdout/stderr concurrently to avoid deadlocks on large outputs
        final class PipeCollector: @unchecked Sendable {
            private var buffer = Data()
            private let lock = NSLock()
            func append(_ chunk: Data) {
                lock.lock(); buffer.append(chunk); lock.unlock()
            }

            func takeRemaining(from handle: FileHandle) {
                let rest = handle.readDataToEndOfFile()
                if !rest.isEmpty { append(rest) }
            }

            var data: Data { lock.lock(); defer { lock.unlock() }; return buffer }
            var count: Int { lock.lock(); defer { lock.unlock() }; return buffer.count }
        }

        let stdoutCollector = PipeCollector()
        let stderrCollector = PipeCollector()
        let outHandle = outputPipe.fileHandleForReading
        let errHandle = errorPipe.fileHandleForReading
        outHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { stdoutCollector.append(chunk) }
        }
        errHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { stderrCollector.append(chunk) }
        }

        do {
            try process.run()

            var didTimeout = false
            if let timeout = timeoutSeconds {
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    process.waitUntilExit()
                    group.leave()
                }
                let result = group.wait(timeout: .now() + timeout)
                if result == .timedOut {
                    didTimeout = true
                    process.terminate()
                }
            } else {
                process.waitUntilExit()
            }

            // Stop handlers and read any remaining bytes
            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil
            stdoutCollector.takeRemaining(from: outHandle)
            stderrCollector.takeRemaining(from: errHandle)

            if didTimeout {
                Env.debug("simctl timed out after \(timeoutSeconds ?? 0)s. args=\(fullArguments.joined(separator: " "))")
                throw SimulatorError.operationTimeout
            }

            if process.terminationStatus != 0 {
                let stderrText = String(data: stderrCollector.data, encoding: .utf8) ?? ""
                let stdoutText = String(data: stdoutCollector.data, encoding: .utf8) ?? ""

                // Many simctl errors print to stdout instead of stderr; prefer stderr, fall back to stdout.
                let primaryMessage: String = {
                    let trimmedErr = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedErr.isEmpty { return trimmedErr }
                    let trimmedOut = stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedOut.isEmpty { return trimmedOut }
                    return "Unknown error"
                }()

                // Emit a concise debug summary with both streams for troubleshooting.
                let previewOut = stdoutText.prefix(200)
                let previewErr = stderrText.prefix(200)
                Env.debug("simctl failed. code=\(process.terminationStatus) stdout=\(previewOut) stderr=\(previewErr)")

                // If JSON was requested and the tool likely doesn't support it, probe without --json
                if requiresJSON {
                    let lower = primaryMessage.lowercased()
                    let mentionsJSONUnsupported = lower.contains("unrecognized") || lower.contains("unknown option") || lower
                        .contains("--json")
                    if mentionsJSONUnsupported {
                        if let probe = try? executeSimctlCommand(arguments: arguments, requiresJSON: false),
                           let probePreview = String(data: probe.prefix(200), encoding: .utf8)
                        {
                            throw SimulatorError
                                .simctlCommandFailed(
                                    "simctl's JSON output may not be supported by your Xcode. Please update Xcode (Xcode 9+). Raw output preview: \(probePreview)...",
                                )
                        } else {
                            throw SimulatorError
                                .simctlCommandFailed(
                                    "simctl's JSON output may not be supported by your Xcode. Please update Xcode (Xcode 9+). Error: \(primaryMessage)",
                                )
                        }
                    }
                }

                throw SimulatorError.simctlCommandFailed(primaryMessage)
            }

            if requiresJSON {
                let preview = String(data: stdoutCollector.data.prefix(200), encoding: .utf8) ?? "<non-utf8>"
                Env.debug("JSON bytes=\(stdoutCollector.count). preview=\(preview)")
            }

            return stdoutCollector.data
        } catch let error as SimulatorError {
            throw error
        } catch {
            throw SimulatorError.simctlCommandFailed("Failed to execute simctl command: \(error.localizedDescription)")
        }
    }

    /// Parses JSON data from simctl command output
    /// - Parameters:
    ///   - data: The JSON data to parse
    ///   - type: The expected type to decode
    /// - Returns: The decoded object
    /// - Throws: SimulatorError if parsing fails
    private func parseJSONOutput<T: Codable>(_ data: Data, as type: T.Type) throws -> T {
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(type, from: data)
        } catch {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8>"
            Env.debug("JSON decode failed. preview=\(preview)")
            throw SimulatorError.simctlCommandFailed("Failed to parse JSON output: \(error.localizedDescription)")
        }
    }

    /// Finds the xcrun executable path
    /// - Returns: Path to xcrun executable
    /// - Throws: SimulatorError if xcrun is not found
    private static func findXcrunPath() throws -> String {
        let possiblePaths = [
            "/usr/bin/xcrun",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/xcrun",
            "/Library/Developer/CommandLineTools/usr/bin/xcrun",
        ]

        let fileManager = FileManager.default

        for path in possiblePaths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }

        // Try to find xcrun using which command
        let process = Process()
        process.launchPath = "/usr/bin/which"
        process.arguments = ["xcrun"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty
                {
                    return path
                }
            }
        } catch {
            // Fall through to error
        }

        throw SimulatorError.simctlCommandFailed("xcrun command not found. Please ensure Xcode Command Line Tools are installed.")
    }

    /// Finds a simulator device by identifier (name or UUID)
    /// - Parameter identifier: The device name or UUID
    /// - Returns: The matching SimulatorDevice
    /// - Throws: SimulatorError if device is not found
    private func findDevice(by identifier: String) throws -> SimulatorDevice {
        let devices = try listDevices()

        // First try to find by UUID
        if let device = devices.first(where: { $0.udid == identifier }) {
            return device
        }

        // Then try to find by name
        if let device = devices.first(where: { $0.name == identifier }) {
            return device
        }

        throw SimulatorError.deviceNotFound(identifier)
    }

    // MARK: - Public Methods

    /// Lists all available simulator devices
    /// - Returns: Array of SimulatorDevice objects
    /// - Throws: SimulatorError if the operation fails
    func listDevices() throws -> [SimulatorDevice] {
        let data = try executeSimctlCommand(arguments: ["list", "devices"], requiresJSON: true)
        let response = try parseJSONOutput(data, as: SimctlDeviceListResponse.self)

        var devices: [SimulatorDevice] = []

        for (runtimeName, deviceList) in response.devices {
            for deviceData in deviceList {
                let device = SimulatorDevice(
                    udid: deviceData.udid,
                    name: deviceData.name,
                    state: SimulatorState(rawValue: deviceData.state) ?? .shutdown,
                    deviceTypeIdentifier: deviceData.deviceTypeIdentifier ?? "",
                    runtimeIdentifier: runtimeName,
                    isAvailable: deviceData.isAvailable ?? true,
                )
                devices.append(device)
            }
        }

        Env.debug("Parsed devices count: \(devices.count)")
        return devices
    }

    /// Starts a simulator device
    /// - Parameter identifier: The device name or UUID to start
    /// - Throws: SimulatorError if the operation fails
    func startSimulator(identifier: String) throws {
        let device = try findDevice(by: identifier)

        // Check if device is already running
        if device.state.isRunning {
            throw SimulatorError.deviceAlreadyRunning(identifier)
        }

        // Check if device is available
        guard device.isAvailable else {
            throw SimulatorError.deviceNotFound(identifier)
        }

        // Execute boot command
        _ = try executeSimctlCommand(arguments: ["boot", device.udid])

        // Verify the device started successfully
        try verifyDeviceStarted(device.udid)
    }

    /// Starts a simulator, allowing disambiguation by runtime when specifying by name
    /// - Parameters:
    ///   - identifier: Device name or UUID
    ///   - runtimeFilter: Optional runtime filter (e.g. "iOS 17", "17.0", or a runtime identifier)
    func startSimulator(identifier: String, runtimeFilter: String?) throws {
        // If no filter provided, defer to existing implementation
        guard let rf = runtimeFilter?.trimmingCharacters(in: .whitespacesAndNewlines), !rf.isEmpty else {
            try startSimulator(identifier: identifier)
            return
        }

        // If identifier is a UUID, ignore runtime filter and just start it (with the same validations)
        do {
            let uuidRegex = try NSRegularExpression(pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
            let range = NSRange(location: 0, length: identifier.utf16.count)
            if uuidRegex.firstMatch(in: identifier, options: [], range: range) != nil {
                try startSimulator(identifier: identifier)
                return
            }
        } catch {
            // If regex fails for any reason, we simply proceed with name-based selection
        }

        // Name-based selection with runtime disambiguation
        let devices = try listDevices()
        let candidates = devices.filter { $0.name == identifier }
            .filter { Filters.runtimeMatches(filter: rf, runtimeIdentifier: $0.runtimeIdentifier) }

        guard !candidates.isEmpty else {
            throw SimulatorError.deviceNotFound(identifier)
        }

        // If multiple candidates match, pick the newest runtime by version
        let selected = candidates.max(by: { versionLess(versionInts(from: $0.runtimeIdentifier), versionInts(from: $1.runtimeIdentifier)) })!

        // Validations similar to startSimulator(identifier:)
        if selected.state.isRunning {
            throw SimulatorError.deviceAlreadyRunning(identifier)
        }
        guard selected.isAvailable else {
            throw SimulatorError.deviceNotFound(identifier)
        }

        _ = try executeSimctlCommand(arguments: ["boot", selected.udid])
        try verifyDeviceStarted(selected.udid)
    }

    private func versionInts(from identifier: String) -> [Int] {
        let parts = identifier.split(separator: ".")
        guard let last = parts.last else { return [] }
        var s = String(last)
        for p in ["iOS-", "watchOS-", "tvOS-"] {
            s = s.replacingOccurrences(of: p, with: "")
        }
        let dot = s.replacingOccurrences(of: "-", with: ".")
        return dot.split(separator: ".").compactMap { Int($0) }
    }

    private func versionLess(_ a: [Int], _ b: [Int]) -> Bool {
        let n = max(a.count, b.count)
        for i in 0 ..< n {
            let ai = i < a.count ? a[i] : 0
            let bi = i < b.count ? b[i] : 0
            if ai != bi { return ai < bi }
        }
        return false
    }

    /// Stops a simulator device or all running devices
    /// - Parameter identifier: The device name or UUID to stop. If nil, stops all running devices
    /// - Throws: SimulatorError if the operation fails
    func stopSimulator(identifier: String? = nil) throws {
        if let identifier {
            // Stop specific device; if multiple devices have the same name, prefer a running one.
            let devices = try listDevices()

            // If it's a UUID, pick by UDID directly
            if let targetByUUID = devices.first(where: { $0.udid == identifier }) {
                if !targetByUUID.state.isRunning { throw SimulatorError.deviceNotRunning(identifier) }
                _ = try executeSimctlCommand(arguments: ["shutdown", targetByUUID.udid])
                try verifyDeviceStopped(targetByUUID.udid)
                return
            }

            // Name-based selection
            let nameMatches = devices.filter { $0.name == identifier }
            guard !nameMatches.isEmpty else { throw SimulatorError.deviceNotFound(identifier) }

            // Prefer a running device among same-name candidates
            let selected = nameMatches.first(where: { $0.state.isRunning }) ?? nameMatches.first!

            // Check if device is already stopped
            if !selected.state.isRunning {
                throw SimulatorError.deviceNotRunning(identifier)
            }

            // Execute shutdown command
            _ = try executeSimctlCommand(arguments: ["shutdown", selected.udid])

            // Verify the device stopped successfully
            try verifyDeviceStopped(selected.udid)
        } else {
            // Stop all running devices
            _ = try executeSimctlCommand(arguments: ["shutdown", "all"])

            // Verify all devices are stopped
            try verifyAllDevicesStopped()
        }
    }

    /// Verifies that a device has started successfully
    /// - Parameter deviceUUID: The UUID of the device to verify
    /// - Throws: SimulatorError if verification fails
    private func verifyDeviceStarted(_ deviceUUID: String) throws {
        let maxAttempts = 10
        let delayBetweenAttempts: TimeInterval = 1.0

        for attempt in 1 ... maxAttempts {
            let devices = try listDevices()

            if let device = devices.first(where: { $0.udid == deviceUUID }) {
                switch device.state {
                case .booted:
                    return // Successfully started
                case .booting:
                    // Still booting, wait and try again
                    Thread.sleep(forTimeInterval: delayBetweenAttempts)
                    continue
                case .shutdown, .shuttingDown:
                    throw SimulatorError.simctlCommandFailed("Device failed to start")
                }
            }

            if attempt == maxAttempts {
                throw SimulatorError.operationTimeout
            }
        }
    }

    /// Verifies that a device has stopped successfully
    /// - Parameter deviceUUID: The UUID of the device to verify
    /// - Throws: SimulatorError if verification fails
    private func verifyDeviceStopped(_ deviceUUID: String) throws {
        let maxAttempts = 10
        let delayBetweenAttempts: TimeInterval = 1.0

        for attempt in 1 ... maxAttempts {
            let devices = try listDevices()

            if let device = devices.first(where: { $0.udid == deviceUUID }) {
                switch device.state {
                case .shutdown:
                    return // Successfully stopped
                case .shuttingDown:
                    // Still shutting down, wait and try again
                    Thread.sleep(forTimeInterval: delayBetweenAttempts)
                    continue
                case .booted, .booting:
                    throw SimulatorError.simctlCommandFailed("Device failed to stop")
                }
            }

            if attempt == maxAttempts {
                throw SimulatorError.operationTimeout
            }
        }
    }

    /// Resets a simulator device (erases all data and settings)
    /// - Parameter identifier: The device name or UUID to reset
    /// - Throws: SimulatorError if the operation fails
    func resetSimulator(identifier: String) throws {
        let device = try findDevice(by: identifier)

        // If device is running, stop it first
        if device.state.isRunning {
            try stopSimulator(identifier: identifier)
        }

        // Execute erase command
        _ = try executeSimctlCommand(arguments: ["erase", device.udid])

        // Note: erase command doesn't require verification as it's immediate
        // The device will remain in shutdown state after erase
    }

    /// Installs an app on a simulator device
    /// - Parameters:
    ///   - bundlePath: Path to the app bundle (.app file)
    ///   - deviceIdentifier: The device name or UUID to install the app on
    /// - Throws: SimulatorError if the operation fails
    func installApp(bundlePath: String, deviceIdentifier: String) throws {
        // Validate app bundle path
        try validateAppBundlePath(bundlePath)

        // Find the target device
        let device = try findDevice(by: deviceIdentifier)

        // Check if device is available
        guard device.isAvailable else {
            throw SimulatorError.deviceNotFound(deviceIdentifier)
        }

        // Device must be booted to install apps
        if !device.state.isRunning {
            throw SimulatorError.deviceNotRunning(deviceIdentifier)
        }

        // Execute install command
        _ = try executeSimctlCommand(arguments: ["install", device.udid, bundlePath])
    }

    /// Creates a new simulator device
    /// - Parameters:
    ///   - name: Name for the new simulator
    ///   - deviceType: Device type identifier
    ///   - runtime: Runtime identifier
    /// - Returns: UUID of the created simulator
    /// - Throws: SimulatorError if the operation fails
    func createSimulator(name: String, deviceType: String, runtime: String) throws -> String {
        // Resolve device type input to an identifier (accepts identifier or friendly name)
        let resolvedDeviceType = try resolveDeviceTypeIdentifier(from: deviceType)
        // Resolve runtime input to an identifier (fast path avoids querying runtimes list)
        let resolvedRuntime = try resolveRuntimeIdentifier(from: runtime, forDeviceTypeIdentifier: resolvedDeviceType)

        // Validate device type only (runtime validity is delegated to simctl to avoid slow listings)
        try validateDeviceType(deviceType: resolvedDeviceType)

        // Execute create command
        let data = try executeSimctlCommand(arguments: ["create", name, resolvedDeviceType, resolvedRuntime])

        // Parse the UUID from the output
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty
        else {
            throw SimulatorError.simctlCommandFailed("Failed to create simulator: no UUID returned")
        }

        return output
    }

    /// Validates device type identifier exists (fast path)
    private func validateDeviceType(deviceType: String) throws {
        let availableDeviceTypes = try getAvailableDeviceTypes()
        guard availableDeviceTypes.contains(where: { $0.identifier == deviceType }) else {
            throw SimulatorError.invalidDeviceType(deviceType)
        }
    }

    /// Resolves a device type input (identifier or human-readable name) to a device type identifier
    /// - Parameter from: The user-provided device type string (e.g., identifier or "iPhone 16")
    /// - Returns: A valid device type identifier
    /// - Throws: SimulatorError.invalidDeviceType if it cannot be resolved
    private func resolveDeviceTypeIdentifier(from input: String) throws -> String {
        let needle = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { throw SimulatorError.invalidDeviceType(input) }

        let types = try getAvailableDeviceTypes()

        // 1) Exact identifier match
        if types.contains(where: { $0.identifier == needle }) {
            return needle
        }

        // Lowercased for case-insensitive comparisons
        let lower = needle.lowercased()

        // 2) Exact name match (case-insensitive)
        if let t = types.first(where: { $0.name.lowercased() == lower }) {
            return t.identifier
        }

        // 3) Display name match (case-insensitive)
        if let t = types.first(where: { $0.displayName.lowercased() == lower }) {
            return t.identifier
        }

        // 4) Hyphen/space normalization: e.g., "iPhone-16" -> "iPhone 16"
        let normalized = lower.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "  ", with: " ")
        if let t = types.first(where: { $0.name.lowercased() == normalized || $0.displayName.lowercased() == normalized }) {
            return t.identifier
        }

        // 5) Prefix match as a last resort (choose the most recent model name)
        let prefixCandidates = types.filter { $0.name.lowercased().hasPrefix(lower) || $0.displayName.lowercased().hasPrefix(lower) }
        if let t = prefixCandidates.sorted(by: { $0.name.count > $1.name.count }).first {
            return t.identifier
        }

        throw SimulatorError.invalidDeviceType(input)
    }

    /// Resolves a runtime input (identifier or human-friendly) to a runtime identifier.
    /// Accepts examples like: "com.apple.CoreSimulator.SimRuntime.iOS-17-0", "iOS 17", "iOS 26.0", "17", "17.0".
    /// If a device type identifier is provided, prefer runtimes matching that platform.
    private func resolveRuntimeIdentifier(from input: String, forDeviceTypeIdentifier deviceTypeId: String?) throws -> String {
        let needle = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { throw SimulatorError.invalidRuntime(input) }

        // Fast path: if input looks like an identifier or a common human-friendly form, build the identifier directly.
        if let built = buildRuntimeIdentifier(from: needle, hintDeviceType: deviceTypeId) {
            return built
        }

        let runtimes = try getAvailableRuntimes()
        // 1) Exact identifier match
        if let r = runtimes.first(where: { $0.identifier == needle }) {
            return r.identifier
        }

        // Platform preference from device type (if available)
        var platformFilter: ((Runtime) -> Bool)? = nil
        if let deviceTypeId {
            if let types = try? getAvailableDeviceTypes(),
               let dt = types.first(where: { $0.identifier == deviceTypeId })
            {
                if dt.isiPhone || dt.isiPad {
                    platformFilter = { $0.isiOS }
                } else if dt.isWatch {
                    platformFilter = { $0.isWatchOS }
                } else if dt.isTV {
                    platformFilter = { $0.isTvOS }
                }
            }
        }

        var candidates = runtimes
        if let pf = platformFilter { candidates = candidates.filter(pf) }

        // 2) Flexible match via identifier/display heuristics
        let matched = candidates.filter { rt in
            Filters.runtimeMatches(filter: needle, runtimeIdentifier: rt.identifier)
        }
        if !matched.isEmpty {
            // Choose the newest by version
            let best = matched.max { a, b in versionLess(versionInts(from: a.identifier), versionInts(from: b.identifier)) }!
            return best.identifier
        }

        // 3) Try matching against name/displayName directly
        let lower = needle.lowercased()
        let nameExact = candidates.first(where: { $0.name.lowercased() == lower })
        if let r = nameExact { return r.identifier }

        let displayExact = candidates.first(where: { "\($0.name) (\($0.version))".lowercased() == lower })
        if let r = displayExact { return r.identifier }

        // 4) Version-only: pick runtimes whose version equals or starts with the input
        let versionToken: String? = {
            let comps = lower.split(whereSeparator: { !("0" ... "9").contains($0) && $0 != "." })
            // Find first numeric-ish component
            return comps.first.map(String.init)
        }()
        if let v = versionToken, !v.isEmpty {
            let exact = candidates.filter { $0.version == v }
            if let r = exact.max(by: { versionLess(versionInts(from: $0.identifier), versionInts(from: $1.identifier)) }) {
                return r.identifier
            }
            let prefix = candidates.filter { $0.version.hasPrefix(v) }
            if let r = prefix.max(by: { versionLess(versionInts(from: $0.identifier), versionInts(from: $1.identifier)) }) {
                return r.identifier
            }
        }

        throw SimulatorError.invalidRuntime(input)
    }

    /// Attempts to construct a runtime identifier from human-friendly input without querying simctl runtimes.
    /// Examples accepted: "iOS 17", "iOS 17.0", "17", "17.0", "watchOS 11", "tvOS 17".
    private func buildRuntimeIdentifier(from input: String, hintDeviceType: String?) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("com.apple.CoreSimulator.SimRuntime.") {
            return trimmed
        }

        // Detect platform from input or device type hint
        func platform(from input: String, hint: String?) -> String {
            let lower = input.lowercased()
            if lower.contains("watchos") || lower.contains("watch") { return "watchOS" }
            if lower.contains("tvos") || lower.contains("tv") { return "tvOS" }
            if let hint {
                if hint.contains("Watch") { return "watchOS" }
                if hint.contains("TV") { return "tvOS" }
            }
            return "iOS"
        }

        let plat = platform(from: trimmed, hint: hintDeviceType)

        // Extract first numeric token (version)
        let lower = trimmed.lowercased()
        let versionChars = Set("0123456789.")
        var version = ""
        var started = false
        for ch in lower {
            if versionChars.contains(ch) {
                version.append(ch)
                started = true
            } else if started {
                break
            }
        }
        guard !version.isEmpty else { return nil }

        let hyphenVersion = version.replacingOccurrences(of: ".", with: "-")
        return "com.apple.CoreSimulator.SimRuntime.\(plat)-\(hyphenVersion)"
    }

    /// Gets available device types
    /// - Returns: Array of DeviceType objects
    /// - Throws: SimulatorError if the operation fails
    func getAvailableDeviceTypes() throws -> [DeviceType] {
        // Fast path: parse plain-text which is typically quicker and reliable.
        if let plainData = try? executeSimctlCommand(arguments: ["list", "devicetypes"], requiresJSON: false, timeoutSeconds: 10),
           let text = String(data: plainData, encoding: .utf8)
        {
            let parsed = parsePlainDeviceTypesOutput(text)
            if !parsed.isEmpty {
                return parsed
            }
        }

        // Fallback to JSON for precision if plain parse returns nothing.
        let data = try executeSimctlCommand(arguments: ["list", "devicetypes"], requiresJSON: true, timeoutSeconds: 30)
        let response = try parseJSONOutput(data, as: SimctlDeviceTypesResponse.self)

        return response.devicetypes.map { deviceTypeData in
            DeviceType(
                identifier: deviceTypeData.identifier,
                name: deviceTypeData.name,
            )
        }
    }

    /// Parses plain-text output from `simctl list devicetypes` into DeviceType objects.
    /// Example line: "iPhone 15 (com.apple.CoreSimulator.SimDeviceType.iPhone-15)"
    private func parsePlainDeviceTypesOutput(_ text: String) -> [DeviceType] {
        var types: [DeviceType] = []

        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            // Skip headers or unrelated lines
            if line.hasPrefix("==") { continue }
            if !line.contains("com.apple.CoreSimulator.SimDeviceType") { continue }

            // Use the last pair of parentheses as identifier container to handle names with parentheses
            guard let lastOpen = line.lastIndex(of: "("), let lastClose = line.lastIndex(of: ")"), lastOpen < lastClose else {
                continue
            }

            let idRange = line.index(after: lastOpen) ..< lastClose
            let identifier = String(line[idRange])
            guard identifier.contains("com.apple.CoreSimulator.SimDeviceType") else { continue }

            let name = String(line[..<lastOpen]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                types.append(DeviceType(identifier: identifier, name: name))
            }
        }

        // Deduplicate by identifier while keeping the first occurrence
        var seen: Set<String> = []
        var unique: [DeviceType] = []
        for t in types {
            if !seen.contains(t.identifier) {
                seen.insert(t.identifier)
                unique.append(t)
            }
        }
        return unique
    }

    /// Gets available runtimes
    /// - Returns: Array of Runtime objects
    /// - Throws: SimulatorError if the operation fails
    func getAvailableRuntimes() throws -> [Runtime] {
        let data = try executeSimctlCommand(arguments: ["list", "runtimes"], requiresJSON: true, timeoutSeconds: 30)
        let response = try parseJSONOutput(data, as: SimctlRuntimesResponse.self)

        return response.runtimes.map { runtimeData in
            Runtime(
                identifier: runtimeData.identifier,
                name: runtimeData.name,
                version: runtimeData.version,
                isAvailable: runtimeData.isAvailable ?? true,
            )
        }
    }

    // Removed plain-text runtime parsing: JSON is required for runtimes.

    /// Validates that the app bundle path exists and is valid
    /// - Parameter bundlePath: Path to validate
    /// - Throws: SimulatorError if the path is invalid
    private func validateAppBundlePath(_ bundlePath: String) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        // Check if path exists
        guard fileManager.fileExists(atPath: bundlePath, isDirectory: &isDirectory) else {
            throw SimulatorError.appBundleNotFound(bundlePath)
        }

        // Check if it's a directory (app bundles are directories)
        guard isDirectory.boolValue else {
            throw SimulatorError.appBundleNotFound(bundlePath)
        }

        // Check if it has .app extension
        guard bundlePath.hasSuffix(".app") else {
            throw SimulatorError.appBundleNotFound(bundlePath)
        }

        // Check if Info.plist exists inside the bundle
        let infoPlistPath = (bundlePath as NSString).appendingPathComponent("Info.plist")
        guard fileManager.fileExists(atPath: infoPlistPath) else {
            throw SimulatorError.appBundleNotFound(bundlePath)
        }
    }

    /// Deletes a simulator device
    /// - Parameter identifier: The device name or UUID to delete
    /// - Throws: SimulatorError if the operation fails
    func deleteSimulator(identifier: String) throws {
        let device = try findDevice(by: identifier)

        // If device is running, stop it first
        if device.state.isRunning {
            try stopSimulator(identifier: identifier)
        }

        // Execute delete command
        _ = try executeSimctlCommand(arguments: ["delete", device.udid])

        // Verify the device was deleted
        try verifyDeviceDeleted(device.udid)
    }

    /// Deletes multiple simulator devices in a single simctl invocation
    /// - Parameter udids: Array of device UDIDs to delete
    /// - Throws: SimulatorError if the operation fails
    func deleteSimulators(udids: [String]) throws {
        let uniqueUdids = Array(Set(udids)).filter { !$0.isEmpty }
        guard !uniqueUdids.isEmpty else { return }

        // Best-effort: stop running devices first
        let devices = try listDevices()
        let running = devices.filter { uniqueUdids.contains($0.udid) && $0.state.isRunning }
        for d in running {
            try? stopSimulator(identifier: d.udid)
        }

        // Perform a single bulk delete
        _ = try executeSimctlCommand(arguments: ["delete"] + uniqueUdids)

        // Verify deletion
        try verifyDevicesDeleted(uniqueUdids)
    }

    /// Best-effort check that a device has been deleted.
    /// Note: single-shot check; logs a debug warning if still present, but does not throw.
    private func verifyDeviceDeleted(_ deviceUUID: String) throws {
        let devices = try listDevices()
        if devices.contains(where: { $0.udid == deviceUUID }) {
            Env.debug("Deletion not yet reflected for \(deviceUUID); proceeding without failure")
        }
    }

    /// Best-effort check for bulk deletion.
    /// Note: single-shot check; logs remaining UDIDs in debug, but does not throw.
    private func verifyDevicesDeleted(_ deviceUUIDs: [String]) throws {
        let target = Set(deviceUUIDs)
        let devices = try listDevices()
        let remaining = Set(devices.map(\.udid)).intersection(target)
        if !remaining.isEmpty {
            Env.debug("Bulk deletion not fully reflected; remaining: \(remaining.joined(separator: ", "))")
        }
    }

    /// Verifies that all devices have stopped successfully
    /// - Throws: SimulatorError if verification fails
    private func verifyAllDevicesStopped() throws {
        let maxAttempts = 10
        let delayBetweenAttempts: TimeInterval = 1.0

        for attempt in 1 ... maxAttempts {
            let devices = try listDevices()
            let runningDevices = devices.filter(\.state.isRunning)

            if runningDevices.isEmpty {
                return // All devices stopped
            }

            if attempt == maxAttempts {
                throw SimulatorError.operationTimeout
            }

            Thread.sleep(forTimeInterval: delayBetweenAttempts)
        }
    }

    // MARK: - Initialization

    init() throws {
        xcrunPath = try SimulatorService.findXcrunPath()
        // Debug
        Env.debug("Using xcrun at path: \(xcrunPath)")
        // NOTE: for debugging code.
        // try validateSimctlAvailability()
    }

    // MARK: - Diagnostics

    struct DoctorReport {
        let xcrunPath: String
        let simctlAvailable: Bool
        let jsonSupported: Bool
        let notes: [String]
    }

    /// Performs environment diagnosis: simctl availability and JSON support.
    func diagnoseEnvironment() throws -> DoctorReport {
        var simctlOK = true
        var jsonOK = true
        var notes: [String] = []

        // Check simctl availability
        do {
            _ = try executeSimctlCommand(arguments: ["help"], requiresJSON: false, timeoutSeconds: 5)
        } catch {
            simctlOK = false
            notes.append("simctl is not available. Ensure Xcode and CLT are installed.")
        }

        // Check JSON support (devices list)
        if simctlOK {
            do {
                _ = try executeSimctlCommand(arguments: ["list", "devices"], requiresJSON: true, timeoutSeconds: 8)
            } catch {
                jsonOK = false
                notes.append("simctl JSON output not supported or failed. Update Xcode (9+) or avoid --json paths.")
            }
        }

        return DoctorReport(xcrunPath: xcrunPath, simctlAvailable: simctlOK, jsonSupported: jsonOK, notes: notes)
    }
}

// MARK: - Supporting Types for JSON Parsing

private struct SimctlDeviceListResponse: Codable {
    let devices: [String: [SimctlDeviceData]]
}

private struct SimctlDeviceData: Codable {
    let udid: String
    let name: String
    let state: String
    let deviceTypeIdentifier: String?
    let isAvailable: Bool?
}

private struct SimctlDeviceTypesResponse: Codable {
    let devicetypes: [SimctlDeviceTypeData]
}

private struct SimctlDeviceTypeData: Codable {
    let identifier: String
    let name: String
}

private struct SimctlRuntimesResponse: Codable {
    let runtimes: [SimctlRuntimeData]
}

private struct SimctlRuntimeData: Codable {
    let identifier: String
    let name: String
    let version: String
    let isAvailable: Bool?
}
