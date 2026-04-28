// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FFmpegGUI-Rewrap",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FFmpegGUI-Rewrap",
            path: "Sources/FFmpegGUIRewrap",
            // Binaries are copied into the .app by the Makefile; exclude them
            // from SPM's resource pipeline to suppress "unhandled file" warnings.
            exclude: ["Resources/bin"]
        )
    ]
)
