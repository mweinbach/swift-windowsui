// swift-tools-version: 6.2
import PackageDescription

// The scene contract, CPU rasterizer, geometry, and layout engine have no
// window-system dependency. Keep their SwiftPM closure equally portable: a
// Linux or macOS package must never resolve WinSDK, Direct2D, or UI Automation
// merely to use one of these products.
var products: [Product] = [
    .library(name: "SwiftWindowsCore", targets: ["SwiftWindowsCore"]),
    .library(name: "SwiftWindowsGraphics", targets: ["SwiftWindowsGraphics"]),
    .library(name: "SwiftWindowsLayout", targets: ["SwiftWindowsLayout"]),
    .library(name: "SwiftWindowsScene", targets: ["SwiftWindowsScene"]),
]

var targets: [Target] = [
    .target(name: "SwiftWindowsCore"),
    .target(
        name: "SwiftWindowsGraphics",
        dependencies: ["SwiftWindowsCore"]
    ),
    .target(
        name: "SwiftWindowsLayout",
        dependencies: ["SwiftWindowsCore"]
    ),
    .target(
        name: "SwiftWindowsScene",
        dependencies: ["SwiftWindowsCore", "SwiftWindowsGraphics"]
    ),
    .testTarget(
        name: "SwiftWindowsPortableTests",
        dependencies: [
            "SwiftWindowsCore",
            "SwiftWindowsGraphics",
            "SwiftWindowsLayout",
            "SwiftWindowsScene",
        ]
    ),
]

#if os(Windows)
    products += [
        .library(name: "SwiftWindowsUI", targets: ["SwiftWindowsUI"]),
        .library(name: "WinSwiftUI", targets: ["WinSwiftUI"]),
        .library(name: "SwiftWindowsDemo", targets: ["SwiftWindowsDemo"]),
        .library(name: "SwiftWindowsApp", targets: ["SwiftWindowsApp"]),
        .executable(name: "swift-windowsui", targets: ["swift-windowsui"]),
        .executable(name: "swift-windowsui-snapshot", targets: ["swift-windowsui-snapshot"]),
        .executable(name: "swift-windowsui-gallery", targets: ["swift-windowsui-gallery"]),
        .executable(name: "macos-reference-renderer", targets: ["macos-reference-renderer"]),
    ]

    targets += [
        .target(
            name: "CDirect2DInterop",
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("D2d1")]
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
            name: "SwiftWindowsPlatform",
            dependencies: ["SwiftWindowsCore", "CUIAInterop"]
        ),
        .target(
            name: "SwiftWindowsRendererD3D11",
            dependencies: ["SwiftWindowsCore", "SwiftWindowsGraphics", "CDirect2DInterop"],
            linkerSettings: [.linkedLibrary("D3DCompiler")]
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
        // WinSwiftUI is renderer-neutral: the executable composition root,
        // not the facade, selects the concrete Direct3D 11 backend.
        .target(
            name: "WinSwiftUI",
            dependencies: [
                "SwiftWindowsCore",
                "SwiftWindowsGraphics",
                "SwiftWindowsLayout",
                "SwiftWindowsPlatform",
                "SwiftWindowsUI",
            ],
            linkerSettings: [.linkedLibrary("Shell32")]
        ),
        .target(
            name: "SwiftWindowsDemo",
            dependencies: ["WinSwiftUI"]
        ),
        // The Windows composition root is the only target that pairs the
        // renderer-neutral WinSwiftUI facade with the D3D11 GPU backend.
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
                "SwiftWindowsUI",
                "WinSwiftUI",
            ]
        ),
        // This remains a helpful explanatory stub on Windows while its real
        // SwiftUI/AppKit implementation is available on macOS below.
        .executableTarget(name: "macos-reference-renderer"),
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
#elseif os(macOS)
    // The exact same dashboard and @main entry point import Apple's SwiftUI
    // on macOS. Neither target needs WinSwiftUI, a Win32 host, or D3D11.
    products += [
        .library(name: "SwiftWindowsDemo", targets: ["SwiftWindowsDemo"]),
        .executable(name: "swift-windowsui", targets: ["swift-windowsui"]),
        .executable(name: "macos-reference-renderer", targets: ["macos-reference-renderer"]),
    ]

    targets += [
        .target(name: "SwiftWindowsDemo"),
        .executableTarget(
            name: "swift-windowsui",
            dependencies: ["SwiftWindowsDemo"]
        ),
        .executableTarget(name: "macos-reference-renderer"),
    ]
#endif

let package = Package(
    name: "swift-windowsui",
    platforms: [.macOS(.v15)],
    products: products,
    targets: targets
)
