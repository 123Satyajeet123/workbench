// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WorkbenchCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WorkbenchCore", targets: ["WorkbenchCore"]),
        .executable(name: "workbench-pages", targets: ["WorkbenchPages"]),
    ],
    targets: [
        .target(name: "WorkbenchCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "WorkbenchPages", dependencies: ["WorkbenchCore"]),
        .testTarget(name: "WorkbenchCoreTests", dependencies: ["WorkbenchCore"]),
    ]
)
