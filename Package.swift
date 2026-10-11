// swift-tools-version: 6.0
import PackageDescription

// Hub Settings - одно окно с настройками всех приложений набора.
// Собирается без Xcode, только Command Line Tools: ./build.sh
let package = Package(
    name: "HubSettings",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SuiteKit"),
    ],
    targets: [
        .executableTarget(
            name: "HubSettings",
            dependencies: ["SuiteKit"]
        ),
    ]
)
