// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vessel",
    platforms: [
        .macOS("15.0")
    ],
    dependencies: [
        .package(url: "https://github.com/apple/containerization.git", revision: "9275f365dd555c8f072e7d250d809f5eb7bdd746"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Vessel",
            dependencies: [
                .product(name: "Containerization", package: "containerization"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/Vessel"
        )
    ]
)
