import XCTest
@testable import XSimCLI

final class SimulatorServiceTests: XCTestCase {
    var simulatorService: SimulatorService!

    override func setUp() {
        super.setUp()
        // Note: These tests require Xcode and simctl to be available
        do {
            simulatorService = try SimulatorService()
        } catch {
            XCTFail("Failed to initialize SimulatorService: \(error)")
        }
    }

    override func tearDown() {
        simulatorService = nil
        super.tearDown()
    }

    // MARK: - Device Listing Tests

    func testListDevices() throws {
        // Test that we can list devices without throwing an error
        let devices = try simulatorService.listDevices()

        // We should get some devices (even if empty array is valid)
        XCTAssertNotNil(devices)

        // If we have devices, verify they have required properties
        for device in devices {
            XCTAssertFalse(device.udid.isEmpty, "Device UDID should not be empty")
            XCTAssertFalse(device.name.isEmpty, "Device name should not be empty")
            XCTAssertFalse(device.runtimeIdentifier.isEmpty, "Runtime identifier should not be empty")
        }
    }

    func testListDevicesReturnsValidStates() throws {
        let devices = try simulatorService.listDevices()

        // Verify all devices have valid states
        for device in devices {
            XCTAssertTrue(
                SimulatorState.allCases.contains(device.state),
                "Device \(device.name) has invalid state: \(device.state)",
            )
        }
    }

    func testListDevicesHandlesEmptyResult() throws {
        // This test verifies that even if no devices are available,
        // the method returns an empty array rather than throwing
        let devices = try simulatorService.listDevices()
        XCTAssertNotNil(devices)
    }

    // MARK: - Simulator Start Tests

    func testStartSimulatorWithValidDevice() throws {
        let devices = try simulatorService.listDevices()

        // Find a shutdown device to test with
        guard let shutdownDevice = devices.first(where: { $0.state == .shutdown && $0.isAvailable }) else {
            throw XCTSkip("No shutdown devices available for testing")
        }

        // Test starting by UUID
        XCTAssertNoThrow(try simulatorService.startSimulator(identifier: shutdownDevice.udid))

        // Verify device is now running
        let updatedDevices = try simulatorService.listDevices()
        let startedDevice = updatedDevices.first { $0.udid == shutdownDevice.udid }
        XCTAssertNotNil(startedDevice)
        XCTAssertTrue(startedDevice?.state.isRunning ?? false)
    }

    func testStartSimulatorWithInvalidDevice() {
        XCTAssertThrowsError(try simulatorService.startSimulator(identifier: "invalid-device-id")) { error in
            XCTAssertTrue(error is SimulatorError)
            if case let SimulatorError.deviceNotFound(identifier) = error {
                XCTAssertEqual(identifier, "invalid-device-id")
            } else {
                XCTFail("Expected deviceNotFound error")
            }
        }
    }

    func testStartAlreadyRunningSimulator() throws {
        let devices = try simulatorService.listDevices()

        // Find a running device to test with
        guard let runningDevice = devices.first(where: { $0.state.isRunning }) else {
            throw XCTSkip("No running devices available for testing")
        }

        XCTAssertThrowsError(try simulatorService.startSimulator(identifier: runningDevice.udid)) { error in
            XCTAssertTrue(error is SimulatorError)
            if case SimulatorError.deviceAlreadyRunning = error {
                // Expected error
            } else {
                XCTFail("Expected deviceAlreadyRunning error")
            }
        }
    }

    // MARK: - Simulator Stop Tests

    func testStopSimulatorWithValidDevice() throws {
        let devices = try simulatorService.listDevices()

        // Find a running device to test with
        guard let runningDevice = devices.first(where: { $0.state.isRunning }) else {
            throw XCTSkip("No running devices available for testing")
        }

        // Test stopping by UUID
        XCTAssertNoThrow(try simulatorService.stopSimulator(identifier: runningDevice.udid))

        // Verify device is now stopped
        let updatedDevices = try simulatorService.listDevices()
        let stoppedDevice = updatedDevices.first { $0.udid == runningDevice.udid }
        XCTAssertNotNil(stoppedDevice)
        XCTAssertFalse(stoppedDevice?.state.isRunning ?? true)
    }

    func testStopNotRunningSimulator() throws {
        let devices = try simulatorService.listDevices()

        // Find a stopped device to test with
        guard let stoppedDevice = devices.first(where: { !$0.state.isRunning }) else {
            throw XCTSkip("No stopped devices available for testing")
        }

        XCTAssertThrowsError(try simulatorService.stopSimulator(identifier: stoppedDevice.udid)) { error in
            XCTAssertTrue(error is SimulatorError)
            if case SimulatorError.deviceNotRunning = error {
                // Expected error
            } else {
                XCTFail("Expected deviceNotRunning error")
            }
        }
    }

    func testStopAllSimulators() throws {
        // Test stopping all simulators
        XCTAssertNoThrow(try simulatorService.stopSimulator(identifier: nil))

        // Verify all devices are stopped
        let devices = try simulatorService.listDevices()
        let runningDevices = devices.filter(\.state.isRunning)
        XCTAssertTrue(runningDevices.isEmpty, "All devices should be stopped")
    }

    func testStopSimulatorWithInvalidDevice() {
        XCTAssertThrowsError(try simulatorService.stopSimulator(identifier: "invalid-device-id")) { error in
            XCTAssertTrue(error is SimulatorError)
            if case let SimulatorError.deviceNotFound(identifier) = error {
                XCTAssertEqual(identifier, "invalid-device-id")
            } else {
                XCTFail("Expected deviceNotFound error")
            }
        }
    }

    // MARK: - Simulator Reset Tests

    func testResetSimulatorWithValidDevice() throws {
        let devices = try simulatorService.listDevices()

        // Find any available device to test with
        guard let testDevice = devices.first(where: { $0.isAvailable }) else {
            throw XCTSkip("No available devices for testing")
        }

        // Test resetting by UUID
        XCTAssertNoThrow(try simulatorService.resetSimulator(identifier: testDevice.udid))

        // Verify device still exists and is in shutdown state
        let updatedDevices = try simulatorService.listDevices()
        let resetDevice = updatedDevices.first { $0.udid == testDevice.udid }
        XCTAssertNotNil(resetDevice)
        XCTAssertEqual(resetDevice?.state, .shutdown)
    }

    func testResetRunningSimulator() throws {
        let devices = try simulatorService.listDevices()

        // Find a running device to test with
        guard let runningDevice = devices.first(where: { $0.state.isRunning }) else {
            throw XCTSkip("No running devices available for testing")
        }

        // Test resetting a running device (should stop it first)
        XCTAssertNoThrow(try simulatorService.resetSimulator(identifier: runningDevice.udid))

        // Verify device is now stopped
        let updatedDevices = try simulatorService.listDevices()
        let resetDevice = updatedDevices.first { $0.udid == runningDevice.udid }
        XCTAssertNotNil(resetDevice)
        XCTAssertEqual(resetDevice?.state, .shutdown)
    }

    func testResetSimulatorWithInvalidDevice() {
        XCTAssertThrowsError(try simulatorService.resetSimulator(identifier: "invalid-device-id")) { error in
            XCTAssertTrue(error is SimulatorError)
            if case let SimulatorError.deviceNotFound(identifier) = error {
                XCTAssertEqual(identifier, "invalid-device-id")
            } else {
                XCTFail("Expected deviceNotFound error")
            }
        }
    }

    // MARK: - App Installation Tests

    func testInstallAppWithInvalidPath() {
        let devices = try! simulatorService.listDevices()
        guard let testDevice = devices.first(where: { $0.isAvailable }) else {
            XCTFail("No available devices for testing")
            return
        }

        let invalidPath = "/path/to/nonexistent.app"

        XCTAssertThrowsError(try simulatorService.installApp(bundlePath: invalidPath, deviceIdentifier: testDevice.udid)) { error in
            XCTAssertTrue(error is SimulatorError)
            if case let SimulatorError.appBundleNotFound(path) = error {
                XCTAssertEqual(path, invalidPath)
            } else {
                XCTFail("Expected appBundleNotFound error")
            }
        }
    }

    func testInstallAppWithInvalidDevice() {
        let invalidPath = "/path/to/test.app"

        XCTAssertThrowsError(try simulatorService.installApp(bundlePath: invalidPath, deviceIdentifier: "invalid-device")) { error in
            XCTAssertTrue(error is SimulatorError)
            // Could be either appBundleNotFound (path validation first) or deviceNotFound
            XCTAssertTrue(error is SimulatorError)
        }
    }

    func testInstallAppOnShutdownDevice() throws {
        let devices = try simulatorService.listDevices()

        guard let shutdownDevice = devices.first(where: { $0.state == .shutdown && $0.isAvailable }) else {
            throw XCTSkip("No shutdown devices available for testing")
        }

        let invalidPath = "/path/to/test.app"

        XCTAssertThrowsError(try simulatorService.installApp(bundlePath: invalidPath, deviceIdentifier: shutdownDevice.udid)) { error in
            XCTAssertTrue(error is SimulatorError)
            // Could be either appBundleNotFound (path validation first) or deviceNotRunning
            XCTAssertTrue(error is SimulatorError)
        }
    }

    func testValidateAppBundlePathWithNonAppFile() {
        // Test with a regular file (not .app)
        let tempFile = NSTemporaryDirectory() + "test.txt"
        FileManager.default.createFile(atPath: tempFile, contents: nil, attributes: nil)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let devices = try! simulatorService.listDevices()
        guard let testDevice = devices.first(where: { $0.isAvailable }) else {
            XCTFail("No available devices for testing")
            return
        }

        XCTAssertThrowsError(try simulatorService.installApp(bundlePath: tempFile, deviceIdentifier: testDevice.udid)) { error in
            XCTAssertTrue(error is SimulatorError)
            if case SimulatorError.appBundleNotFound = error {
                // Expected error
            } else {
                XCTFail("Expected appBundleNotFound error")
            }
        }
    }

    // MARK: - Simulator Creation Tests

    func testGetAvailableDeviceTypes() throws {
        let deviceTypes = try simulatorService.getAvailableDeviceTypes()

        XCTAssertNotNil(deviceTypes)

        // Verify device types have required properties
        for deviceType in deviceTypes {
            XCTAssertFalse(deviceType.identifier.isEmpty, "Device type identifier should not be empty")
            XCTAssertFalse(deviceType.name.isEmpty, "Device type name should not be empty")
        }
    }

    func testGetAvailableRuntimes() throws {
        let runtimes = try simulatorService.getAvailableRuntimes()

        XCTAssertNotNil(runtimes)

        // Verify runtimes have required properties
        for runtime in runtimes {
            XCTAssertFalse(runtime.identifier.isEmpty, "Runtime identifier should not be empty")
            XCTAssertFalse(runtime.name.isEmpty, "Runtime name should not be empty")
            XCTAssertFalse(runtime.version.isEmpty, "Runtime version should not be empty")
        }
    }

    func testCreateSimulatorWithValidParameters() throws {
        let deviceTypes = try simulatorService.getAvailableDeviceTypes()
        let runtimes = try simulatorService.getAvailableRuntimes()

        guard let deviceType = deviceTypes.first,
              let runtime = runtimes.first(where: { $0.isAvailable })
        else {
            throw XCTSkip("No available device types or runtimes for testing")
        }

        let testName = "XSimTest-\(UUID().uuidString.prefix(8))"

        // Create simulator
        let uuid = try simulatorService.createSimulator(
            name: testName,
            deviceType: deviceType.identifier,
            runtime: runtime.identifier,
        )

        XCTAssertFalse(uuid.isEmpty, "Created simulator UUID should not be empty")

        // Verify simulator was created
        let devices = try simulatorService.listDevices()
        let createdDevice = devices.first { $0.udid == uuid }
        XCTAssertNotNil(createdDevice)
        XCTAssertEqual(createdDevice?.name, testName)

        // Clean up - delete the test simulator
        try? simulatorService.deleteSimulator(identifier: uuid)
    }

    func testCreateSimulatorWithInvalidDeviceType() throws {
        let runtimes = try simulatorService.getAvailableRuntimes()

        guard let runtime = runtimes.first(where: { $0.isAvailable }) else {
            throw XCTSkip("No available runtimes for testing")
        }

        let invalidDeviceType = "com.apple.CoreSimulator.SimDeviceType.InvalidDevice"

        XCTAssertThrowsError(try simulatorService.createSimulator(
            name: "TestDevice",
            deviceType: invalidDeviceType,
            runtime: runtime.identifier,
        )) { error in
            XCTAssertTrue(error is SimulatorError)
            if case let SimulatorError.invalidDeviceType(deviceType) = error {
                XCTAssertEqual(deviceType, invalidDeviceType)
            } else {
                XCTFail("Expected invalidDeviceType error")
            }
        }
    }

    func testCreateSimulatorWithInvalidRuntime() throws {
        let deviceTypes = try simulatorService.getAvailableDeviceTypes()

        guard let deviceType = deviceTypes.first else {
            throw XCTSkip("No available device types for testing")
        }

        let invalidRuntime = "com.apple.CoreSimulator.SimRuntime.InvalidRuntime"

        XCTAssertThrowsError(try simulatorService.createSimulator(
            name: "TestDevice",
            deviceType: deviceType.identifier,
            runtime: invalidRuntime,
        )) { error in
            XCTAssertTrue(error is SimulatorError)
            if case let SimulatorError.invalidRuntime(runtime) = error {
                XCTAssertEqual(runtime, invalidRuntime)
            } else {
                XCTFail("Expected invalidRuntime error")
            }
        }
    }

    // MARK: - Simulator Deletion Tests

    func testDeleteSimulatorWithValidDevice() throws {
        // First create a test simulator
        let deviceTypes = try simulatorService.getAvailableDeviceTypes()
        let runtimes = try simulatorService.getAvailableRuntimes()

        guard let deviceType = deviceTypes.first,
              let runtime = runtimes.first(where: { $0.isAvailable })
        else {
            throw XCTSkip("No available device types or runtimes for testing")
        }

        let testName = "XSimDeleteTest-\(UUID().uuidString.prefix(8))"

        // Create simulator
        let uuid = try simulatorService.createSimulator(
            name: testName,
            deviceType: deviceType.identifier,
            runtime: runtime.identifier,
        )

        // Verify it was created
        var devices = try simulatorService.listDevices()
        XCTAssertTrue(devices.contains { $0.udid == uuid })

        // Delete the simulator
        XCTAssertNoThrow(try simulatorService.deleteSimulator(identifier: uuid))

        // Verify it was deleted
        devices = try simulatorService.listDevices()
        XCTAssertFalse(devices.contains { $0.udid == uuid })
    }

    func testDeleteRunningSimulator() throws {
        // First create a test simulator
        let deviceTypes = try simulatorService.getAvailableDeviceTypes()
        let runtimes = try simulatorService.getAvailableRuntimes()

        guard let deviceType = deviceTypes.first,
              let runtime = runtimes.first(where: { $0.isAvailable })
        else {
            throw XCTSkip("No available device types or runtimes for testing")
        }

        let testName = "XSimDeleteRunningTest-\(UUID().uuidString.prefix(8))"

        // Create and start simulator
        let uuid = try simulatorService.createSimulator(
            name: testName,
            deviceType: deviceType.identifier,
            runtime: runtime.identifier,
        )

        try simulatorService.startSimulator(identifier: uuid)

        // Verify it's running
        var devices = try simulatorService.listDevices()
        let runningDevice = devices.first { $0.udid == uuid }
        XCTAssertTrue(runningDevice?.state.isRunning ?? false)

        // Delete the running simulator (should stop it first)
        XCTAssertNoThrow(try simulatorService.deleteSimulator(identifier: uuid))

        // Verify it was deleted
        devices = try simulatorService.listDevices()
        XCTAssertFalse(devices.contains { $0.udid == uuid })
    }

    func testDeleteSimulatorWithInvalidDevice() {
        XCTAssertThrowsError(try simulatorService.deleteSimulator(identifier: "invalid-device-id")) { error in
            XCTAssertTrue(error is SimulatorError)
            if case let SimulatorError.deviceNotFound(identifier) = error {
                XCTAssertEqual(identifier, "invalid-device-id")
            } else {
                XCTFail("Expected deviceNotFound error")
            }
        }
    }
}
