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
        .testTarget(
            name: "PistonTests",
            dependencies: ["Piston"]
        )
    ]
)
