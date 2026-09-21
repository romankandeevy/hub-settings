// swift-tools-version: 6.0
import PackageDescription

// Hub Settings - одно окно с настройками всех приложений набора.
// Собирается без Xcode, только Command Line Tools: ./build.sh
let package = Package(
    name: "HubSettings",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../SuiteKit"),
        // Живые превью - это настоящие интерфейсы острова и панели, а не их рисунки.
        .package(path: "../island"),
        .package(path: "../sidebar"),
    ],
    targets: [
        .executableTarget(
            name: "HubSettings",
            dependencies: [
                "SuiteKit",
                .product(name: "IslandUI", package: "island"),
                .product(name: "SidebarUI", package: "sidebar"),
            ]
        ),
    ]
)
