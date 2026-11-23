// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WorkbenchUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WorkbenchUI", targets: ["WorkbenchUI"])
    ],
    dependencies: [
        .package(path: "../WorkbenchCore"), .package(path: "../BaseKit"), .package(path: "../Kernel"),
    ],
    targets: [
        .target(
            name: "WorkbenchUI",
            dependencies: [
                "WorkbenchCore",
                .product(name: "Kernel", package: "Kernel"),
                .product(name: "AgentCLI", package: "BaseKit"),
                .product(name: "CaptureService", package: "BaseKit"),
                .product(name: "LocalSources", package: "BaseKit"),
                .product(name: "WebResearch", package: "BaseKit"),
                .product(name: "TelegramReader", package: "BaseKit"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "WorkbenchUITests",
            dependencies: [
                "WorkbenchUI", .product(name: "AgentCLI", package: "BaseKit"),
                .product(name: "Kernel", package: "Kernel"), .product(name: "TelegramReader", package: "BaseKit"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
