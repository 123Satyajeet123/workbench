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
        .library(name: "TelegramReader", targets: ["TelegramReader"]),
        .executable(name: "transcribe-bakeoff", targets: ["TranscribeBakeoff"]),
    ],
    dependencies: [
        .package(path: "../WorkbenchCore"),
        .package(url: "https://github.com/Swiftgram/TDLibKit", exact: "1.5.2-tdlib-1.8.70-03220f6b"),
    ],
    targets: [
        .target(name: "AgentCLI", dependencies: ["WorkbenchCore"]),
        .target(name: "LocalSources", dependencies: ["WorkbenchCore"]),
        .target(name: "WebResearch", dependencies: ["WorkbenchCore"]),
        .target(
            name: "TelegramReader",
            dependencies: ["WorkbenchCore", "LocalSources", .product(name: "TDLibKit", package: "TDLibKit")]),
        .target(name: "CaptureService", dependencies: ["WorkbenchCore", "LocalSources"]),
        .executableTarget(name: "TranscribeBakeoff", dependencies: ["LocalSources", "WorkbenchCore"]),
        .testTarget(name: "AgentCLITests", dependencies: ["AgentCLI"]),
        .testTarget(name: "LocalSourcesTests", dependencies: ["LocalSources"]),
        .testTarget(name: "WebResearchTests", dependencies: ["WebResearch", "WorkbenchCore"]),
        .testTarget(name: "TelegramReaderTests", dependencies: ["TelegramReader", "WorkbenchCore"]),
        .testTarget(name: "CaptureServiceTests", dependencies: ["CaptureService"]),
    ]
)
