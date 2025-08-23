import Foundation

/// Service class for managing iOS Simulator operations through simctl
class SimulatorService {
    // MARK: - Private Properties

    private let simctlPath = "/usr/bin/xcrun"

    // MARK: - Core simctl Execution Utilities

    /// Executes a simctl command and returns the output
    /// - Parameters:
    ///   - arguments: The simctl command arguments
    ///   - requiresJSON: Whether the command should return JSON output
    /// - Returns: The command output as Data
    /// - Throws: SimulatorError if the command fails
    private func executeSimctlCommand(arguments: [String], requiresJSON: Bool = false) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: simctlPath)

        var fullArguments = ["simctl"]
        fullArguments.append(contentsOf: arguments)

        // Add JSON output flag if required
        if requiresJSON, !arguments.contains("--json") {
            fullArguments.insert("--json", at: 1)
        }

        process.arguments = fullArguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            if process.terminationStatus != 0 {
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw SimulatorError.simctlCommandFailed(errorMessage)
            }

            return outputData
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
            throw SimulatorError.simctlCommandFailed("Failed to parse JSON output: \(error.localizedDescription)")
        }
    }

    /// Validates that simctl is available on the system
    /// - Throws: SimulatorError if simctl is not available
    private func validateSimctlAvailability() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: simctlPath) else {
            throw SimulatorError.simctlCommandFailed("xcrun command not found. Please ensure Xcode Command Line Tools are installed.")
        }

        // Test basic simctl availability
        do {
            _ = try executeSimctlCommand(arguments: ["help"])
        } catch {
            throw SimulatorError.simctlCommandFailed("simctl is not available. Please ensure Xcode is properly installed.")
        }
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

    /// Stops a simulator device or all running devices
    /// - Parameter identifier: The device name or UUID to stop. If nil, stops all running devices
    /// - Throws: SimulatorError if the operation fails
    func stopSimulator(identifier: String? = nil) throws {
        if let identifier {
            // Stop specific device
            let device = try findDevice(by: identifier)

            // Check if device is already stopped
            if !device.state.isRunning {
                throw SimulatorError.deviceNotRunning(identifier)
            }

            // Execute shutdown command
            _ = try executeSimctlCommand(arguments: ["shutdown", device.udid])

            // Verify the device stopped successfully
            try verifyDeviceStopped(device.udid)
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
        // Validate device type and runtime
        try validateDeviceTypeAndRuntime(deviceType: deviceType, runtime: runtime)

        // Execute create command
        let data = try executeSimctlCommand(arguments: ["create", name, deviceType, runtime])

        // Parse the UUID from the output
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty
        else {
            throw SimulatorError.simctlCommandFailed("Failed to create simulator: no UUID returned")
        }

        return output
    }

    /// Gets available device types
    /// - Returns: Array of DeviceType objects
    /// - Throws: SimulatorError if the operation fails
    func getAvailableDeviceTypes() throws -> [DeviceType] {
        let data = try executeSimctlCommand(arguments: ["list", "devicetypes"], requiresJSON: true)
        let response = try parseJSONOutput(data, as: SimctlDeviceTypesResponse.self)

        return response.devicetypes.map { deviceTypeData in
            DeviceType(
                identifier: deviceTypeData.identifier,
                name: deviceTypeData.name,
            )
        }
    }

    /// Gets available runtimes
    /// - Returns: Array of Runtime objects
    /// - Throws: SimulatorError if the operation fails
    func getAvailableRuntimes() throws -> [Runtime] {
        let data = try executeSimctlCommand(arguments: ["list", "runtimes"], requiresJSON: true)
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

    /// Validates device type and runtime identifiers
    /// - Parameters:
    ///   - deviceType: Device type identifier to validate
    ///   - runtime: Runtime identifier to validate
    /// - Throws: SimulatorError if validation fails
    private func validateDeviceTypeAndRuntime(deviceType: String, runtime: String) throws {
        let availableDeviceTypes = try getAvailableDeviceTypes()
        let availableRuntimes = try getAvailableRuntimes()

        // Validate device type
        guard availableDeviceTypes.contains(where: { $0.identifier == deviceType }) else {
            throw SimulatorError.invalidDeviceType(deviceType)
        }

        // Validate runtime
        guard availableRuntimes.contains(where: { $0.identifier == runtime && $0.isAvailable }) else {
            throw SimulatorError.invalidRuntime(runtime)
        }
    }

    /// Verifies that a device has been deleted successfully
    /// - Parameter deviceUUID: The UUID of the device to verify
    /// - Throws: SimulatorError if verification fails
    private func verifyDeviceDeleted(_ deviceUUID: String) throws {
        let maxAttempts = 5
        let delayBetweenAttempts: TimeInterval = 0.5

        for attempt in 1 ... maxAttempts {
            let devices = try listDevices()

            // If device is no longer in the list, deletion was successful
            if !devices.contains(where: { $0.udid == deviceUUID }) {
                return
            }

            if attempt == maxAttempts {
                throw SimulatorError.simctlCommandFailed("Device deletion verification failed")
            }

            Thread.sleep(forTimeInterval: delayBetweenAttempts)
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
        try validateSimctlAvailability()
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
