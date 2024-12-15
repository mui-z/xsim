import Foundation
import Rainbow
import SwiftCLI

public class XSimCLI {
    public init() {}
    public func run() -> Never {
        Rainbow.enabled = Term.isTTY

        let cli = CLI(name: "xsim", version: "0.0.1", description: "xsim")

        cli.commands = [
            Hello(),
            List(),
            // Launch()
        ]

        cli.goAndExit()
    }
}
