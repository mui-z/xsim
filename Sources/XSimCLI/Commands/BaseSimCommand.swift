import Foundation

class BaseSimCommand {
    var simulatorService: SimulatorService?

    func getService() throws -> SimulatorService {
        if let service = simulatorService { return service }
        let service = try SimulatorService()
        simulatorService = service
        return service
    }

    func findDevice(in devices: [SimulatorDevice], identifier: String) -> SimulatorDevice? {
        if let device = devices.first(where: { $0.udid == identifier }) { return device }
        return devices.first(where: { $0.name == identifier })
    }
}
