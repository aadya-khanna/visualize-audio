// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VisualizeAudio",
    platforms: [
        // The Core Audio process tap (ProcessTap.swift) requires 14.4 specifically.
        .macOS("14.4")
    ],
    targets: [
        .executableTarget(
            name: "VisualizeAudio",
            path: "Sources/VisualizeAudio"
        )
    ]
)
