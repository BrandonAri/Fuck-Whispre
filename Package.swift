// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FuckWisprFlow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "FuckWisprFlow", targets: ["FuckWisprFlow"])],
    targets: [
        .executableTarget(
            name: "FuckWisprFlow",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "FuckWisprFlowTests",
            dependencies: ["FuckWisprFlow"]
        )
    ]
)
