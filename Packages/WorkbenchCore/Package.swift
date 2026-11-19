// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WorkbenchCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WorkbenchCore", targets: ["WorkbenchCore"])
    ],
    targets: [
        .target(name: "WorkbenchCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "WorkbenchCoreTests", dependencies: ["WorkbenchCore"]),
    ]
)
