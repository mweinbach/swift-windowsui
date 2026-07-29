import SwiftWindowsDemo

#if canImport(SwiftUI)
    import SwiftUI
#else
    import SwiftWindowsGraphics
    import SwiftWindowsRendererD3D11
    import WinSwiftUI
#endif
@main
struct SwiftWindowsUIDemoApp: App {
    private let model = DemoDashboardModel()

    init() {}

    #if !canImport(SwiftUI)
        /// Composition root (Phase 8 modularization): the Windows product pins
        /// the D3D11 GPU backend here, at the executable that assembles the
        /// app. The `WinSwiftUI` facade itself is renderer-neutral — its
        /// default `renderBackendFactory()` is the software presenter that
        /// ships with the facade — so library consumers no longer link
        /// `SwiftWindowsRendererD3D11` transitively.
        static func renderBackendFactory() -> RenderBackendFactory {
            D3D11RenderBackendFactory()
        }
    #endif

    var body: some Scene {
        // The id registers the scene with the window coordinator so the
        // settings screen's `openWindow(id:)` can spawn additional windows
        // hosting the same content.
        WindowGroup("Swift Windows UI", id: "main-dashboard") {
            DemoRootView(model: model)
        }
    }
}
