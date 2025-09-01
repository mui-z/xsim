import Foundation
import XSimCLI

// If invoked with no subcommand, attempt default behavior in the library.
if DefaultRunner.runIfNoArgs() {
    exit(0)
}

let cli = XSimCLI()
cli.run()
