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
                .product(name: "GRDB", package: "GRDB.swift"), .product(name: "Kernel", package: "Kernel"),
                .product(name: "Lines", package: "Kernel"),
            ]),
        .executableTarget(name: "WorkbenchPages", dependencies: ["WorkbenchCore"]),
        .testTarget(
            name: "WorkbenchCoreTests",
            dependencies: [
                "WorkbenchCore", .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Lines", package: "Kernel"),
            ]),
    ]
)
