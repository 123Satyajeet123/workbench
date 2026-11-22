// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Kernel",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "Kernel", targets: ["Kernel"]),
        .library(name: "Lines", targets: ["Lines"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "5.1.2"),
        .package(url: "https://github.com/x-sheep/swift-property-based.git", exact: "2.0.1"),
    ],
    targets: [
        .target(name: "Kernel", dependencies: [.product(name: "Crypto", package: "swift-crypto")]),
        .target(name: "Lines", dependencies: ["Kernel"]),
        .executableTarget(name: "KernelBenchmark", dependencies: ["Kernel"]),
        .executableTarget(name: "LinesBenchmark", dependencies: ["Lines"]),
        .testTarget(
            name: "KernelTests",
            dependencies: ["Kernel", "Lines", .product(name: "PropertyBased", package: "swift-property-based")],
            resources: [.copy("Resources")]
        ),
    ]
)
