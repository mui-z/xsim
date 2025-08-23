import Foundation
@preconcurrency import Rainbow
@preconcurrency import SwiftCLI

public class XSimCLI {
    private let cli: CLI

    public init() {
        // Configure Rainbow for colored output
        Rainbow.enabled = true

        // Initialize CLI with basic configuration
        cli = CLI(name: "xsim",
                  version: "1.0.0",
                  description: "Xcode Simulator管理ツール - simctlコマンドを短縮して使いやすくします")

        // Register all commands
        registerCommands()
    }

    public func run() -> Never {
        cli.goAndExit()
    }

    private func registerCommands() {
        // Register all available commands without heavy initialization
        cli.commands = [
            ListCommand(),
            StartCommand(),
            StopCommand(),
            ResetCommand(),
            InstallCommand(),
            CreateCommand(),
            DeleteCommand(),
        ]
    }
}
