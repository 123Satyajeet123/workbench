// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WorkbenchCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WorkbenchCore", targets: ["WorkbenchCore"]),
        .executable(name: "workbench-pages", targets: ["WorkbenchPages"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.12.0"),
        .package(path: "../Kernel"),
    ],
    targets: [
        .target(
            name: "WorkbenchCore",
            dependencies: [
                "PagesRelay", .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Kernel", package: "Kernel"),
                .product(name: "Lines", package: "Kernel"),
            ]),
        .target(name: "PagesRelay"),
        .executableTarget(name: "WorkbenchPages", dependencies: ["PagesRelay"]),
        .executableTarget(name: "LifecycleDryRunTool", dependencies: ["WorkbenchCore"]),
        .executableTarget(name: "WorkObjectsDryRunTool", dependencies: ["WorkbenchCore"]),
        .executableTarget(name: "MailBackfillDryRunTool", dependencies: ["WorkbenchCore"]),
        .executableTarget(name: "ScreenBackfillDryRunTool", dependencies: ["WorkbenchCore"]),
        .testTarget(
            name: "WorkbenchCoreTests",
            dependencies: [
                "WorkbenchCore", .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Lines", package: "Kernel"),
            ]),
    ]
)
