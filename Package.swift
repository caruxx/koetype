// swift-tools-version: 6.0
import PackageDescription

let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "KoeType",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", from: "1.1.0"),
    ],
    targets: [
        .target(name: "KoeTypeCore", swiftSettings: swift5),
        .executableTarget(
            name: "KoeType",
            dependencies: [
                "KoeTypeCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            swiftSettings: swift5
        ),
        .testTarget(name: "KoeTypeCoreTests", dependencies: ["KoeTypeCore"], swiftSettings: swift5),
    ]
)
