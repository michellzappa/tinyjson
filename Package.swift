// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TinyJSON",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "Packages/TinyKit"),
    ],
    targets: [
        .executableTarget(
            name: "TinyJSON",
            dependencies: ["TinyKit"],
            path: "Sources/TinyJSON",
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
