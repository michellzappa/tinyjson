// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TinyJSON",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "Packages/TinyKit"),
    ],
    targets: [
        .executableTarget(
            name: "TinyJSON",
            dependencies: ["TinyKit"],
            path: "Sources/TinyJSON",
            exclude: ["Resources"]
        ),
    ]
)
