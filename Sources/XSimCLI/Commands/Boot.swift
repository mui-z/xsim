
import Foundation

import PathKit
import SwiftCLI

class Boot: Command {
    let name = "list"
    let shortDescription = "list ios"

    func execute() throws {
        print("list")
        let raw = try Task.capture(bash: "xcrun simctl list devices -j").stdout

        guard let data = raw.data(using: .utf8) else {
            print("Failed")
            return
        }

        do {
            let output = try JSONDecoder().decode(ListCommandOutput.self, from: data)
            let devices = output.devices
            let versions = devices.keys.sorted()
            for version in versions {
                guard let versionString = version.split(separator: ".").last else {
                    print("FAILED")
                    return
                }
                print("=== \(versionString) ===")

                guard let devices = devices[version.raw] else {
                    print("FAILED")
                    return
                }

                for device in devices {
                    print(device.name)
                }

                print("")
            }
        } catch {
            print("print \(error)")
            return
        }
    }
}

struct ListCommandOutput: Sendable, Codable {
    let devices: [String: [Simulator]]
}

struct Simulator: Sendable, Codable {
    let dataPath: String
    let dataPathSize: Int
    let logPath: String
    let udid: String
    let isAvailable: Bool
    let deviceTypeIdentifier: String
    let state: String // Shutdown or Booted?
    let name: String
}
