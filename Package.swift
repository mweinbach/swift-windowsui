// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-windowsui",
    products: [
        .library(
            name: "SwiftWindowsUI",
            targets: ["SwiftWindowsUI"]
        ),
        .executable(
            name: "swift-windowsui",
            targets: ["swift-windowsui"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftWindowsCore"
        ),
        .target(
            name: "SwiftWindowsGraphics",
            dependencies: ["SwiftWindowsCore"]
        ),
        .target(
            name: "SwiftWindowsScene",
            dependencies: ["SwiftWindowsCore", "SwiftWindowsGraphics"]
        ),
        .target(
            name: "SwiftWindowsLayout",
            dependencies: ["SwiftWindowsCore"]
        ),
        .target(
            name: "SwiftWindowsPlatform",
            dependencies: ["SwiftWindowsCore"]
        ),
        .target(
            name: "SwiftWindowsRendererD3D11",
            dependencies: ["SwiftWindowsCore", "SwiftWindowsGraphics"],
            linkerSettings: [
                .linkedLibrary("D3DCompiler"),
            ]
        ),
        .target(
            name: "SwiftWindowsUI",
            dependencies: [
                "SwiftWindowsCore",
                "SwiftWindowsGraphics",
                "SwiftWindowsLayout",
                "SwiftWindowsPlatform",
            ]
        ),
        .executableTarget(
            name: "swift-windowsui",
            dependencies: [
                "SwiftWindowsUI",
                "SwiftWindowsRendererD3D11",
            ]
        ),
        .testTarget(
            name: "SwiftWindowsCoreLogicTests",
            dependencies: [
                "SwiftWindowsCore",
                "SwiftWindowsGraphics",
                "SwiftWindowsLayout",
                "SwiftWindowsPlatform",
                "SwiftWindowsRendererD3D11",
                "SwiftWindowsScene",
                "SwiftWindowsUI",
            ]
        ),
    ]
)
