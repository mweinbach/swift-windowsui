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
            name: "SwiftWindowsDemo",
            targets: ["SwiftWindowsDemo"]
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
            name: "swift-windowsui-snapshot",
            targets: ["swift-windowsui-snapshot"]
        ),
        .executable(
            name: "swift-windowsui-gallery",
            targets: ["swift-windowsui-gallery"]
        ),
        .executable(
            name: "macos-reference-renderer",
            targets: ["macos-reference-renderer"]
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
                .linkedLibrary("D2d1")
            ]
        ),
        .target(
            name: "CUIAInterop",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("uiautomationcore"),
                .linkedLibrary("ole32"),
                .linkedLibrary("oleaut32"),
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
            dependencies: ["SwiftWindowsCore", "CUIAInterop"]
        ),
        .target(
            name: "SwiftWindowsRendererD3D11",
            dependencies: ["SwiftWindowsCore", "SwiftWindowsGraphics", "CDirect2DInterop"],
            linkerSettings: [
                .linkedLibrary("D3DCompiler")
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
            ],
            linkerSettings: [
                .linkedLibrary("Shell32")
            ]
        ),
        .target(
            name: "SwiftWindowsDemo",
            dependencies: [
                "WinSwiftUI"
            ]
        ),
        .executableTarget(
            name: "swift-windowsui",
            dependencies: [
                "SwiftWindowsDemo",
                "WinSwiftUI",
            ]
        ),
        .executableTarget(
            name: "swift-windowsui-snapshot",
            dependencies: [
                "SwiftWindowsCore",
                "SwiftWindowsDemo",
                "SwiftWindowsGraphics",
                "WinSwiftUI",
            ]
        ),
        .executableTarget(
            name: "swift-windowsui-gallery",
            dependencies: [
                "SwiftWindowsCore",
                "SwiftWindowsDemo",
                "SwiftWindowsGraphics",
                "WinSwiftUI",
            ]
        ),
        // macOS-only reference renderer — produces PNG snapshots of
        // canonical SwiftUI views for cross-platform parity comparison.
        // No Windows-module dependencies so this builds on a clean
        // macOS toolchain; on Windows the source file compiles to a
        // stub that explains it's macOS-only.
        .executableTarget(
            name: "macos-reference-renderer"
        ),
        .testTarget(
            name: "SwiftWindowsCoreLogicTests",
            dependencies: [
                "CUIAInterop",
                "SwiftWindowsApp",
                "SwiftWindowsCore",
                "SwiftWindowsDemo",
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
