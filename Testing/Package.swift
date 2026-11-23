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
    ],
    dependencies: [.package(path: "../Packages/WorkbenchCore")],
    targets: [
        .target(name: "Evals", dependencies: ["WorkbenchCore"]),
        .executableTarget(name: "ClaimEvalRunner", dependencies: ["Evals", "WorkbenchCore"]),
        .executableTarget(name: "OutboundEvalRunner", dependencies: ["Evals", "WorkbenchCore"]),
        .executableTarget(name: "TranscribeBakeoff", dependencies: ["Evals", "WorkbenchCore"]),
        .executableTarget(name: "KalLabelRunner", dependencies: ["Evals", "WorkbenchCore"]),
        .executableTarget(name: "TrustSimRunner", dependencies: ["Evals"]),
        .testTarget(name: "EvalsTests", dependencies: ["Evals", "WorkbenchCore"]),
    ]
)
