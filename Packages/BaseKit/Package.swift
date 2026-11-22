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
        .executable(name: "transcribe-bakeoff", targets: ["TranscribeBakeoff"]),
    ],
    dependencies: [.package(path: "../WorkbenchCore"), .package(path: "../Kernel")],
    targets: [
        .target(name: "AgentCLI", dependencies: ["WorkbenchCore"]),
        .target(name: "LocalSources", dependencies: ["WorkbenchCore", .product(name: "Lines", package: "Kernel")]),
        .target(name: "WebResearch", dependencies: ["WorkbenchCore"]),
        .target(name: "CaptureService", dependencies: ["WorkbenchCore", "LocalSources"]),
        .executableTarget(name: "TranscribeBakeoff", dependencies: ["LocalSources", "WorkbenchCore"]),
        .testTarget(name: "AgentCLITests", dependencies: ["AgentCLI"]),
        .testTarget(name: "LocalSourcesTests", dependencies: ["LocalSources"]),
        .testTarget(name: "WebResearchTests", dependencies: ["WebResearch", "WorkbenchCore"]),
        .testTarget(name: "CaptureServiceTests", dependencies: ["CaptureService"]),
    ]
)
