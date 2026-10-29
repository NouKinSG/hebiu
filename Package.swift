// swift-tools-version:5.10
import PackageDescription

// HebiuKit：不依赖界面的核心逻辑（配置、事件、待办、提醒、数据来源），有单元测试
// Hebiu：桌宠程序本体（窗口、动画、菜单、设置页），带参数运行时是命令行工具
let package = Package(
    name: "hebiu",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Hebiu", targets: ["Hebiu"]),
        .library(name: "HebiuKit", targets: ["HebiuKit"]),
    ],
    dependencies: [.package(path: "Packages/FocusCore")],
    targets: [
        .target(name: "HebiuKit"),
        .executableTarget(name: "Hebiu", dependencies: ["HebiuKit", .product(name: "FocusCore", package: "FocusCore")]),
        .testTarget(name: "HebiuKitTests", dependencies: ["HebiuKit"]),
    ]
)
