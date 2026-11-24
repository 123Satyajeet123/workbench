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
        .executable(name: "d6-sim", targets: ["D6SimRunner"]),
        .executable(name: "independent-flows", targets: ["IndependentFlowsDemo"]),
        .executable(name: "model-access", targets: ["ModelAccessDemo"]),
        .executable(name: "model-failures", targets: ["ModelFailuresDemo"]),
        .executable(name: "model-call-check", targets: ["ModelCallCheck"]),
        .executable(name: "gallery", targets: ["GalleryDemo"]),
        .executable(name: "demo-builder", targets: ["DemoBuilder"]),
        .executable(name: "search-tools", targets: ["SearchToolsDemo"]),
        .executable(name: "grounding-probe", targets: ["GroundingProbe"]),
        .executable(name: "page-eval", targets: ["PageEvalRunner"]),
        .executable(name: "page-eval-tools", targets: ["PageEvalTools"]),
        .executable(name: "machine-page-render", targets: ["MachinePageRender"]),
        .executable(name: "machine-page-live", targets: ["MachinePageLive"]),
        .executable(name: "judge-probe", targets: ["JudgeProbe"]),
        .executable(name: "machine-roles", targets: ["MachineRolesDemo"]),
        .executable(name: "inject-corpus", targets: ["InjectCorpusCheck"]),
        .executable(name: "objectref", targets: ["ObjectRefDemo"]),
        .executable(name: "store-safety-probe", targets: ["StoreSafetyProbe"]),
        .executable(name: "templates-start", targets: ["TemplatesStartDemo"]),
        .executable(name: "linkedin-import", targets: ["LinkedInImportDemo"]),
        .executable(name: "source-registry", targets: ["SourceRegistryDemo"]),
        .executable(name: "text-rules", targets: ["TextRulesDemo"]),
        .executable(name: "run-settings", targets: ["RunSettingsDemo"]),
        .executable(name: "recall-probe", targets: ["RecallProbe"]),
        .executable(name: "member-identity", targets: ["MemberIdentityDemo"]),
        .executable(name: "bugfix-check", targets: ["BugfixCheck"]),
        .executable(name: "provenance-check", targets: ["ProvenanceCheck"]),
        .executable(name: "provenance-probe", targets: ["ProvenanceProbe"]),
        .executable(name: "run-journal", targets: ["RunJournalDemo"]),
        .executable(name: "add-team", targets: ["AddTeamDemo"]),
        .executable(name: "page-truth", targets: ["PageTruthDemo"]),
        .executable(name: "doc-editor", targets: ["DocEditorDemo"]),
    ],
    dependencies: [
        .package(path: "../Packages/WorkbenchCore"), .package(path: "../Packages/WorkbenchUI"),
        .package(path: "../Packages/BaseKit"), .package(path: "../Packages/Kernel"),
    ],
    targets: [
        .target(name: "PageTools"),
        .executableTarget(name: "PageEvalTools", dependencies: ["PageTools"]),
        .target(
            name: "Evals",
            dependencies: [
                "WorkbenchCore", "PageTools", .product(name: "AgentCLI", package: "BaseKit"),
                .product(name: "Kernel", package: "Kernel"), .product(name: "Lines", package: "Kernel"),
            ],
            resources: [.copy("PageEval/PageEvalFacts.json")]),
        .executableTarget(
            name: "PageEvalRunner",
            dependencies: [
                "Evals", "WorkbenchCore", "WorkbenchUI", .product(name: "AgentCLI", package: "BaseKit"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(name: "ClaimEvalRunner", dependencies: ["Evals", "WorkbenchCore"]),
        .executableTarget(name: "OutboundEvalRunner", dependencies: ["Evals", "WorkbenchCore"]),
        .executableTarget(
            name: "TranscribeBakeoff",
            dependencies: ["Evals", "WorkbenchCore", .product(name: "LocalSources", package: "BaseKit")]),
        .executableTarget(name: "KalLabelRunner", dependencies: ["Evals", "WorkbenchCore"]),
        .executableTarget(name: "TrustSimRunner", dependencies: ["Evals"]),
        .executableTarget(name: "D6SimRunner", dependencies: ["Evals", "WorkbenchCore"]),
        .executableTarget(
            name: "IndependentFlowsDemo",
            dependencies: [
                "WorkbenchCore", "WorkbenchUI", .product(name: "CaptureService", package: "BaseKit"),
                .product(name: "LocalSources", package: "BaseKit"),
                .product(name: "Kernel", package: "Kernel"), .product(name: "Lines", package: "Kernel"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(
            name: "ModelAccessDemo",
            dependencies: ["WorkbenchCore", "WorkbenchUI", .product(name: "AgentCLI", package: "BaseKit")],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(
            name: "ModelCallCheck", dependencies: [.product(name: "AgentCLI", package: "BaseKit")],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(
            name: "ModelFailuresDemo",
            dependencies: ["WorkbenchCore", "WorkbenchUI", .product(name: "AgentCLI", package: "BaseKit")],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(name: "GalleryDemo", dependencies: ["WorkbenchCore"]),
        .executableTarget(name: "TemplatesStartDemo", dependencies: ["WorkbenchCore"]),
        .executableTarget(
            name: "LinkedInImportDemo",
            dependencies: [
                "WorkbenchCore", .product(name: "Kernel", package: "Kernel"),
                .product(name: "Lines", package: "Kernel"),
            ]),
        .target(
            name: "DemoBuild",
            dependencies: [
                "WorkbenchCore", .product(name: "WorkbenchUI", package: "WorkbenchUI"),
                .product(name: "LocalSources", package: "BaseKit"), .product(name: "Kernel", package: "Kernel"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(name: "DemoBuilder", dependencies: ["DemoBuild"]),
        .executableTarget(
            name: "SearchToolsDemo",
            dependencies: [
                "WorkbenchCore", .product(name: "Kernel", package: "Kernel"),
                .product(name: "Lines", package: "Kernel"),
            ]),
        .executableTarget(
            name: "GroundingProbe",
            dependencies: ["Evals", "WorkbenchCore", .product(name: "AgentCLI", package: "BaseKit")]),
        .executableTarget(
            name: "JudgeProbe",
            dependencies: ["Evals", "WorkbenchCore", .product(name: "AgentCLI", package: "BaseKit")]),
        .executableTarget(name: "MachineRolesDemo", dependencies: ["WorkbenchCore"]),
        .executableTarget(name: "SourceRegistryDemo", dependencies: ["WorkbenchCore"]),
        .executableTarget(
            name: "TextRulesDemo", dependencies: ["WorkbenchCore", .product(name: "AgentCLI", package: "BaseKit")],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(
            name: "RunSettingsDemo", dependencies: ["WorkbenchCore", .product(name: "AgentCLI", package: "BaseKit")],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(
            name: "MemberIdentityDemo", dependencies: ["WorkbenchCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(name: "InjectCorpusCheck", dependencies: ["Evals"]),
        .executableTarget(
            name: "RecallProbe",
            dependencies: ["DemoBuild", "Evals", "WorkbenchCore", .product(name: "AgentCLI", package: "BaseKit")],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .target(
            name: "PageSnapshot",
            dependencies: [
                "WorkbenchCore", "WorkbenchUI", .product(name: "Kernel", package: "Kernel"),
                .product(name: "Lines", package: "Kernel"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(
            name: "MachinePageLive",
            dependencies: [
                "PageSnapshot", "WorkbenchCore", "WorkbenchUI", .product(name: "Kernel", package: "Kernel"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(
            name: "MachinePageRender",
            dependencies: [
                "PageSnapshot", "WorkbenchCore", "WorkbenchUI", .product(name: "CaptureService", package: "BaseKit"),
                .product(name: "LocalSources", package: "BaseKit"),
                .product(name: "Kernel", package: "Kernel"), .product(name: "Lines", package: "Kernel"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(
            name: "DocEditorDemo",
            dependencies: [
                "WorkbenchCore", "WorkbenchUI", .product(name: "Kernel", package: "Kernel"),
                .product(name: "Lines", package: "Kernel"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(
            name: "ObjectRefDemo", dependencies: ["WorkbenchCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(
            name: "StoreSafetyProbe",
            dependencies: [
                "WorkbenchCore", .product(name: "Kernel", package: "Kernel"),
                .product(name: "Lines", package: "Kernel"),
            ]),
        .executableTarget(
            name: "BugfixCheck",
            dependencies: [
                "WorkbenchCore", .product(name: "AgentCLI", package: "BaseKit"),
                .product(name: "Kernel", package: "Kernel"), .product(name: "Lines", package: "Kernel"),
            ]),
        .executableTarget(
            name: "ProvenanceCheck",
            dependencies: [
                "WorkbenchCore", .product(name: "Kernel", package: "Kernel"),
                .product(name: "Lines", package: "Kernel"),
            ]),
        .executableTarget(
            name: "ProvenanceProbe",
            dependencies: [
                "WorkbenchCore", .product(name: "Kernel", package: "Kernel"),
                .product(name: "Lines", package: "Kernel"),
            ]),
        .executableTarget(
            name: "RunJournalDemo",
            dependencies: [
                "WorkbenchCore", .product(name: "Kernel", package: "Kernel"),
                .product(name: "Lines", package: "Kernel"),
            ]),
        .executableTarget(name: "AddTeamDemo", dependencies: ["WorkbenchCore"]),
        .executableTarget(
            name: "PageTruthDemo",
            dependencies: [
                "PageSnapshot", "WorkbenchCore", "WorkbenchUI", .product(name: "CaptureService", package: "BaseKit"),
                .product(name: "AgentCLI", package: "BaseKit"), .product(name: "LocalSources", package: "BaseKit"),
                .product(name: "Kernel", package: "Kernel"), .product(name: "Lines", package: "Kernel"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "EvalsTests", dependencies: ["Evals", "WorkbenchCore"]),
    ]
)
