// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WorkbenchUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WorkbenchUI", targets: ["WorkbenchUI"])
    ],
    dependencies: [
        .package(path: "../WorkbenchCore"), .package(path: "../BaseKit"), .package(path: "../GoogleConnector"),
    ],
    targets: [
        .target(
            name: "WorkbenchUI",
            dependencies: [
                "WorkbenchCore", "GoogleConnector",
                .product(name: "AgentCLI", package: "BaseKit"),
                .product(name: "CaptureService", package: "BaseKit"),
                .product(name: "LocalSources", package: "BaseKit"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "WorkbenchUITests",
            dependencies: ["WorkbenchUI", .product(name: "AgentCLI", package: "BaseKit")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
