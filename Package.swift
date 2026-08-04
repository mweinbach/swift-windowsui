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
        // WinSwiftUI is renderer-neutral: it programs against the
        // RenderBackendFactory protocol in SwiftWindowsGraphics and must not
        // depend on a concrete GPU backend. The D3D11 backend is selected by
        // the app composition root (the swift-windowsui executable), which is
        // the only target that pairs WinSwiftUI with SwiftWindowsRendererD3D11.
        .target(
            name: "WinSwiftUI",
            dependencies: [
                "SwiftWindowsCore",
                "SwiftWindowsGraphics",
                "SwiftWindowsLayout",
                "SwiftWindowsPlatform",
                "SwiftWindowsUI",
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
        // Composition root for the Windows product: pairs the renderer-neutral
        // WinSwiftUI facade with the concrete D3D11 GPU backend (see
        // `renderBackendFactory()` in AppEntry.swift).
        .executableTarget(
            name: "swift-windowsui",
            dependencies: [
                "SwiftWindowsDemo",
                "SwiftWindowsGraphics",
                "SwiftWindowsRendererD3D11",
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
                // The interaction-state tier drives `RetainedViewRuntime`
                // input (pointer, Tab) directly, so the gallery names the
                // runtime rather than reaching it transitively through
                // WinSwiftUI.
                "SwiftWindowsUI",
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
