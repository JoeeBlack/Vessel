// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Vessel",
    platforms: [
        .macOS("15.0")
    ],
    dependencies: [
        .package(path: "./containerization"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-system.git", exact: "1.6.5"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-configuration.git", exact: "1.1.0")
    ],
    targets: [
        .target(
            name: "VesselXPC",
            path: "Sources/VesselXPC",
            swiftSettings: [
                .unsafeFlags(["-whole-module-optimization"], .when(configuration: .release))
            ]
        ),
                .executableTarget(
            name: "vesseld",
            dependencies: [
                "VesselXPC",
                .product(name: "Containerization", package: "containerization"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "SystemPackage", package: "swift-system")
            ],
            path: "Sources/vesseld",
            swiftSettings: [
                .unsafeFlags(["-whole-module-optimization"], .when(configuration: .release))
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-dead_strip"])
            ]
        ),
        .executableTarget(
            name: "Vessel",
            dependencies: [
                "VesselXPC",
                .product(name: "Containerization", package: "containerization"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "SystemPackage", package: "swift-system")
            ],
            path: "Sources/Vessel",
            swiftSettings: [
                .unsafeFlags(["-whole-module-optimization"], .when(configuration: .release))
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-dead_strip"], .when(configuration: .release))
            ]
        ),
        .executableTarget(
            name: "vcctl",
            dependencies: [
                "VesselXPC",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/cctl",
            swiftSettings: [
                .unsafeFlags(["-whole-module-optimization"], .when(configuration: .release))
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-dead_strip"], .when(configuration: .release))
            ]
        ),
        .executableTarget(
            name: "VesselHelper",
            path: "Sources/VesselHelper"
        )
    ]
)
