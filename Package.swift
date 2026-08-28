// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SpaceLens",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SpaceLens", targets: ["SpaceLens"])
    ],
    targets: [
        .target(
            name: "SpaceLens",
            path: "SpaceLens",
            exclude: [
                "App",
                "Features/Browser/BreadcrumbView.swift",
                "Features/Browser/ContentView.swift",
                "Features/Browser/NodeRowView.swift",
                "Features/Sunburst",
                "Resources",
                "Shared"
            ],
            sources: [
                "Domain",
                "Scanning",
                "Features/Browser/DiskViewModel.swift"
            ]
        ),
        .testTarget(
            name: "SpaceLensTests",
            dependencies: ["SpaceLens"],
            path: "SpaceLensTests",
            exclude: ["README.md"]
        )
    ],
    swiftLanguageModes: [.v5]
)
