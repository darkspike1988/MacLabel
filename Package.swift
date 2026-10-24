// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacLabelKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MacLabelKit", targets: ["MacLabelKit"]),
        .library(name: "MacLabelApp", targets: ["MacLabelApp"]),
        // For the Xcode target that builds the CLI into MacLabel.app (`simulate` command).
        .library(name: "LabelSimulator", targets: ["LabelSimulator"]),
        .executable(name: "maclabel", targets: ["maclabel"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "LabelProtocol"),
        .target(name: "LabelMedia", dependencies: ["LabelProtocol"], resources: [.process("Resources")]),
        .target(name: "LabelRender", dependencies: ["LabelProtocol", "LabelMedia"]),
        .target(
            name: "LabelTransport",
            dependencies: ["LabelProtocol"],
            linkerSettings: [.linkedFramework("IOUSBHost"), .linkedFramework("IOKit")]
        ),
        .target(name: "LabelSimulator", dependencies: ["LabelProtocol", "LabelMedia"]),
        .target(
            name: "MacLabelKit",
            dependencies: ["LabelProtocol", "LabelMedia", "LabelRender", "LabelTransport"],
            resources: [.process("Localizable.xcstrings")]
        ),
        .target(
            name: "MacLabelApp",
            dependencies: ["MacLabelKit"],
            resources: [.process("Localizable.xcstrings")]
        ),
        .executableTarget(
            name: "maclabel",
            dependencies: [
                "MacLabelKit",
                "LabelSimulator",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "LabelProtocolTests", dependencies: ["LabelProtocol"]),
        .testTarget(name: "LabelMediaTests", dependencies: ["LabelMedia"]),
        .testTarget(name: "LabelRenderTests", dependencies: ["LabelRender", "LabelMedia", "LabelProtocol"]),
        .testTarget(name: "LabelTransportTests", dependencies: ["LabelTransport"]),
        .testTarget(
            name: "LabelSimulatorTests",
            dependencies: ["LabelSimulator", "LabelProtocol", "LabelMedia"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "MacLabelKitTests", dependencies: ["MacLabelKit"]),
        .testTarget(name: "MacLabelAppTests", dependencies: ["MacLabelApp"]),
        .testTarget(name: "maclabelCLITests", dependencies: ["maclabel", "MacLabelKit", "LabelMedia", "LabelTransport"]),
    ],
    swiftLanguageModes: [.v6]
)
