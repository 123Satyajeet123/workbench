// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Testing",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "claim-eval", targets: ["ClaimEvalRunner"]),
        .executable(name: "outbound-eval", targets: ["OutboundEvalRunner"]),
        .executable(name: "transcribe-bakeoff", targets: ["TranscribeBakeoff"]),
        .executable(name: "kal-label", targets: ["KalLabelRunner"]),
        .executable(name: "trust-sim", targets: ["TrustSimRunner"]),
        .executable(name: "independent-flows", targets: ["IndependentFlowsDemo"]),
    ],
    dependencies: [
        .package(path: "../Packages/WorkbenchCore"), .package(path: "../Packages/WorkbenchUI"),
        .package(path: "../Packages/BaseKit"), .package(path: "../Packages/Kernel"),
    ],
    targets: [
        .target(name: "Evals", dependencies: ["WorkbenchCore"]),
        .executableTarget(name: "ClaimEvalRunner", dependencies: ["Evals", "WorkbenchCore"]),
        .executableTarget(name: "OutboundEvalRunner", dependencies: ["Evals", "WorkbenchCore"]),
        .executableTarget(name: "TranscribeBakeoff", dependencies: ["Evals", "WorkbenchCore"]),
        .executableTarget(name: "KalLabelRunner", dependencies: ["Evals", "WorkbenchCore"]),
        .executableTarget(name: "TrustSimRunner", dependencies: ["Evals"]),
        .executableTarget(
            name: "IndependentFlowsDemo",
            dependencies: [
                "WorkbenchCore", "WorkbenchUI", .product(name: "CaptureService", package: "BaseKit"),
                .product(name: "Kernel", package: "Kernel"), .product(name: "Lines", package: "Kernel"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "EvalsTests", dependencies: ["Evals", "WorkbenchCore"]),
    ]
)
