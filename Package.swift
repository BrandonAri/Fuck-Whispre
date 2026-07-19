// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FuckWhispre",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "FuckWhispre", targets: ["FuckWhispre"])],
    targets: [
        .executableTarget(
            name: "FuckWhispre",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "FuckWhispreTests",
            dependencies: ["FuckWhispre"]
        )
    ]
)
