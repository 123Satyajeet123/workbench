// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GoogleConnector",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GoogleConnector", targets: ["GoogleConnector"])
    ],
    dependencies: [.package(url: "https://github.com/openid/AppAuth-iOS.git", exact: "3.0.0")],
    targets: [
        .target(
            name: "GoogleConnector",
            dependencies: [.product(name: "AppAuth", package: "AppAuth-iOS")]
        ),
        .testTarget(name: "GoogleConnectorTests", dependencies: ["GoogleConnector"]),
    ]
)
