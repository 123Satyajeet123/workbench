// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BaseKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AgentCLI", targets: ["AgentCLI"]),
        .library(name: "LocalSources", targets: ["LocalSources"]),
        .library(name: "CaptureService", targets: ["CaptureService"]),
        .library(name: "WebResearch", targets: ["WebResearch"]),
    ],
    dependencies: [.package(path: "../WorkbenchCore"), .package(path: "../Kernel")],
    targets: [
        .target(name: "AgentCLI", dependencies: ["WorkbenchCore"]),
        .target(
            name: "LocalSources",
            dependencies: [
                "WorkbenchCore", .product(name: "Kernel", package: "Kernel"),
                .product(name: "Lines", package: "Kernel"),
            ]),
        .target(name: "WebResearch", dependencies: ["WorkbenchCore"]),
        .target(
            name: "CaptureService",
            dependencies: ["WorkbenchCore", "LocalSources", .product(name: "Kernel", package: "Kernel")]),
        .testTarget(name: "AgentCLITests", dependencies: ["AgentCLI"]),
        .testTarget(name: "LocalSourcesTests", dependencies: ["LocalSources", "CaptureService"]),
        .testTarget(name: "WebResearchTests", dependencies: ["WebResearch", "WorkbenchCore"]),
        .testTarget(name: "CaptureServiceTests", dependencies: ["CaptureService"]),
    ]
)
