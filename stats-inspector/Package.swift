// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "DatadogStatsInspector",
    platforms: [
        .iOS(.v15),
        .tvOS(.v11),
    ],
    products: [
        .library(
            name: "DatadogStatsInspector",
            targets: ["DatadogStatsInspector"]
        ),
    ],
    dependencies: [
        .package(name: "Datadog", path: ".."),
    ],
    targets: [
        .target(
            name: "DatadogStatsInspector",
            dependencies: ["Datadog"]
        ),
        .testTarget(
            name: "DatadogStatsInspectorTests",
            dependencies: ["DatadogStatsInspector"]
        ),
    ]
)
