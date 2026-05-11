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
            dependencies: ["FountainShim"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-force_load",
                    "-Xlinker", "/Users/phil/local/src/fountain/build/libfountain.a"
                ]),
                .linkedLibrary("sqlite3"),
                .linkedLibrary("c++")
            ]
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
