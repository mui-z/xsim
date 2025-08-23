// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftCLIToolTemplate",
    platforms: [.macOS(.v10_15)],
    products: [
        .executable(name: "test", targets: ["SwiftCLIToolTemplate"]),
    ],
    dependencies: [
        .package(url: "https://github.com/onevcat/Rainbow", from: "4.0.1"),
        .package(url: "https://github.com/kylef/PathKit", from: "1.0.0"),
        .package(url: "https://github.com/jakeheis/SwiftCLI", from: "6.0.1"),
    ],
    targets: [
        .executableTarget(name: "SwiftCLIToolTemplate", dependencies: ["SwiftCLIToolTemplateCLI"]),
        .target(name: "SwiftCLIToolTemplateCLI", dependencies: ["SwiftCLIToolTemplateKit", "PathKit", "Rainbow", "SwiftCLI"]),
        .target(name: "SwiftCLIToolTemplateKit", dependencies: ["PathKit", "Rainbow"]),
        .testTarget(
            name: "SwiftCLIToolTemplateTests",
            dependencies: ["SwiftCLIToolTemplate"]
        ),
    ]
)
