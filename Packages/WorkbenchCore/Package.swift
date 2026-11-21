// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WorkbenchCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WorkbenchCore", targets: ["WorkbenchCore"]),
        .executable(name: "workbench-pages", targets: ["WorkbenchPages"]),
        .executable(name: "claim-eval", targets: ["ClaimEvalRunner"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.12.0")
    ],
    targets: [
        .target(name: "WorkbenchCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(name: "WorkbenchPages", dependencies: ["WorkbenchCore"]),
        .executableTarget(name: "ClaimEvalRunner", dependencies: ["WorkbenchCore"]),
        .testTarget(
            name: "WorkbenchCoreTests", dependencies: ["WorkbenchCore", .product(name: "GRDB", package: "GRDB.swift")]),
    ]
)
