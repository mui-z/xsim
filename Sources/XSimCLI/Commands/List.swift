import Foundation

import PathKit
import SwiftCLI

class List: Command {
    let name = "list"
    let shortDescription = "list ios"

    func execute() throws {
        try Task.run(bash: "xcrun simctl list devices")
    }
}
