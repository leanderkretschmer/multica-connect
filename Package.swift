// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MulticaKit",
    platforms: [
        // String form so the package also configures on toolchains older than
        // the one that ships the .v26 enum case.
        .iOS("26.0"),
        .macOS("26.0"),
    ],
    products: [
        .library(name: "MulticaKit", targets: ["MulticaKit"]),
    ],
    targets: [
        .target(
            name: "MulticaKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MulticaKitTests",
            dependencies: ["MulticaKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
