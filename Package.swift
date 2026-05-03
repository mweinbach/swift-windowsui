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
        .library(
            name: "WinSwiftUI",
            targets: ["WinSwiftUI"]
        ),
        .library(
            name: "SwiftWindowsApp",
            targets: ["SwiftWindowsApp"]
        ),
        .executable(
            name: "swift-windowsui",
            targets: ["swift-windowsui"]
        ),
        .executable(
            name: "swift-windowsui-inspect",
            targets: ["swift-windowsui-inspect"]
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
            name: "CDirect2DInterop",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("D2d1"),
                .linkedLibrary("Dwrite"),
            ]
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
            dependencies: ["SwiftWindowsCore", "SwiftWindowsGraphics", "CDirect2DInterop"],
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
                "CDirect2DInterop",
            ]
        ),
        .target(
            name: "SwiftWindowsApp",
            dependencies: [
                "SwiftWindowsUI",
                "SwiftWindowsRendererD3D11",
            ]
        ),
        .target(
            name: "WinSwiftUI",
            dependencies: [
                "SwiftWindowsCore",
                "SwiftWindowsGraphics",
                "SwiftWindowsLayout",
                "SwiftWindowsPlatform",
                "SwiftWindowsUI",
                "SwiftWindowsRendererD3D11",
            ]
        ),
        .executableTarget(
            name: "swift-windowsui",
            dependencies: [
                "WinSwiftUI",
            ]
        ),
        .executableTarget(
            name: "swift-windowsui-inspect",
            dependencies: [
                "SwiftWindowsCore",
                "SwiftWindowsGraphics",
                "SwiftWindowsRendererD3D11",
                "SwiftWindowsUI",
                "WinSwiftUI",
            ]
        ),
        .testTarget(
            name: "SwiftWindowsCoreLogicTests",
            dependencies: [
                "SwiftWindowsApp",
                "SwiftWindowsCore",
                "SwiftWindowsGraphics",
                "SwiftWindowsLayout",
                "SwiftWindowsPlatform",
                "SwiftWindowsRendererD3D11",
                "SwiftWindowsScene",
                "SwiftWindowsUI",
                "WinSwiftUI",
            ]
        ),
    ]
)
