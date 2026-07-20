// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotionTranscribe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotionTranscribe",
            path: "Sources/NotionTranscribe"
        )
    ]
)
