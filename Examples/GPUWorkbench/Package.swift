// swift-tools-version: 6.2
import Foundation
import PackageDescription

// This is a separate package. Copy it outside the toolkit checkout before
// building, and explicitly select the toolkit revision being qualified.
guard let toolkitPath = ProcessInfo.processInfo.environment["SWIFT_WINDOWSUI_CHECKOUT"],
    !toolkitPath.isEmpty,
    NSString(string: toolkitPath).isAbsolutePath
else {
    fatalError("Set SWIFT_WINDOWSUI_CHECKOUT to an absolute swift-windowsui checkout path.")
}
#if !os(Windows)
    fatalError("GPUWorkbench currently qualifies the Windows product only.")
#endif

let package = Package(
    name: "gpu-workbench",
    products: [.executable(name: "GPUWorkbench", targets: ["GPUWorkbench"])],
    dependencies: [.package(name: "swift-windowsui", path: toolkitPath)],
    targets: [
        .executableTarget(
            name: "GPUWorkbench",
            dependencies: [
                .product(name: "WinSwiftUI", package: "swift-windowsui"),
                .product(name: "SwiftWindowsGraphics", package: "swift-windowsui"),
                .product(name: "SwiftWindowsRendererD3D11", package: "swift-windowsui"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "GPUWorkbenchTests", dependencies: ["GPUWorkbench"]),
    ]
)
