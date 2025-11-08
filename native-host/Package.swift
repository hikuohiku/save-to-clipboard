// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SaveToClipboard",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "SaveToClipboard",
            dependencies: [],
            path: "Sources/SaveToClipboard"
        )
    ]
)
