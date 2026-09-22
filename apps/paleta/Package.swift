// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Paleta",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PaletaCore", targets: ["PaletaCore"]),
        .executable(name: "Paleta", targets: ["PaletaApp"])
    ],
    targets: [
        .target(name: "PaletaCore"),
        .executableTarget(
            name: "PaletaApp",
            dependencies: ["PaletaCore"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "PaletaCoreTests", dependencies: ["PaletaCore"])
    ]
)
