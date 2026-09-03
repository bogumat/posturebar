// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PostureBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PostureBar", targets: ["PostureBar"])
    ],
    targets: [
        .executableTarget(
            name: "PostureBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Vision")
            ]
        ),
        .testTarget(
            name: "PostureBarTests",
            dependencies: ["PostureBar"],
            path: "Tests/PostureBarTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
