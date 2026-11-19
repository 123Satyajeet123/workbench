// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BaseKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AgentCLI", targets: ["AgentCLI"]),
        .library(name: "LocalSources", targets: ["LocalSources"]),
        .library(name: "CaptureService", targets: ["CaptureService"]),
        .executable(name: "transcribe-bakeoff", targets: ["TranscribeBakeoff"]),
    ],
    dependencies: [.package(path: "../WorkbenchCore")],
    targets: [
        .target(name: "AgentCLI", dependencies: ["WorkbenchCore"]),
        .target(name: "LocalSources", dependencies: ["WorkbenchCore"]),
        .target(name: "CaptureService", dependencies: ["WorkbenchCore", "LocalSources"]),
        .executableTarget(name: "TranscribeBakeoff", dependencies: ["LocalSources", "WorkbenchCore"]),
        .testTarget(name: "AgentCLITests", dependencies: ["AgentCLI"]),
        .testTarget(name: "LocalSourcesTests", dependencies: ["LocalSources"]),
        .testTarget(name: "CaptureServiceTests", dependencies: ["CaptureService"]),
    ]
)
