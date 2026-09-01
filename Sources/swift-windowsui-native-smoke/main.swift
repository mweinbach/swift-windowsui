import SwiftWindowsRendererD3D11
import WinSwiftUI

/// Deliberately separate from the shared-source demo and its settings store.
/// The retained controller writes only trace.jsonl and result.json in its
/// caller-owned working directory. It has no command-line modes or inputs.
@main
struct NativeOwnedSmokeExecutable {
    @MainActor
    static func main() {
        NativeOwnedSmokeMain.run(
            renderBackendFactory: D3D11RenderBackendFactory(),
            expectedBackendNames: ["D3D11 BATCH", "DIRECT2D", "2D RENDERER"])
    }
}
