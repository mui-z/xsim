// swift-tools-version:6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "XSim",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "xsim", targets: ["XSim"]),
    ],
    dependencies: [
        .package(url: "https://github.com/onevcat/Rainbow", from: "4.0.1"),
        .package(url: "https://github.com/jakeheis/SwiftCLI", from: "6.0.1"),
    ],
    targets: [
        .executableTarget(name: "XSim", dependencies: ["XSimCLI"]),
        .target(name: "XSimCLI", dependencies: ["Rainbow", "SwiftCLI"]),
        // .target(name: "XSimCLI", dependencies: ["XSimKit", "PathKit", "Rainbow", "SwiftCLI"]),
        // .target(name: "XSimKit", dependencies: ["PathKit", "Rainbow"]),
        .testTarget(
            name: "XSimCLITests",
            dependencies: ["XSimCLI"],
        ),
    ],
)
