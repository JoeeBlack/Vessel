// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vessel",
    platforms: [
        .macOS("15.0")
    ],
    dependencies: [
        .package(url: "https://github.com/apple/containerization.git", branch: "main"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Vessel",
            dependencies: [
                .product(name: "Containerization", package: "containerization"),
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/Vessel"
        )
    ]
)
