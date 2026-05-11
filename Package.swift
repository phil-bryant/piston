// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Piston",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Piston",
            targets: ["Piston"]
        ),
        .executable(
            name: "PistonRunner",
            targets: ["PistonRunner"]
        )
    ],
    targets: [
        .target(
            name: "FountainShim",
            publicHeadersPath: "."
        ),
        .target(
            name: "Piston",
            dependencies: ["FountainShim"]
        ),
        .executableTarget(
            name: "PistonRunner",
            dependencies: ["Piston"]
        ),
        .testTarget(
            name: "PistonTests",
            dependencies: ["Piston", "PistonRunner"]
        )
    ]
)
