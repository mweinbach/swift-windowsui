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

    #if !canImport(SwiftUI)
        /// The smallest window the demo's layout is designed to hold, taken
        /// from the demo itself so the number the window enforces and the
        /// number the layout is tested at cannot drift apart. Windows
        /// enforces it through `WM_GETMINMAXINFO`, so the user's drag stops
        /// there rather than continuing into a size the shell has no answer
        /// for.
        private static var minimumWindowSize: IntSize {
            IntSize(
                width: Int32(DemoWindowMetrics.minimumSize.width),
                height: Int32(DemoWindowMetrics.minimumSize.height)
            )
        }
    #endif

    var body: some Scene {
        // The id registers the scene with the window coordinator so the
        // settings screen's `openWindow(id:)` can spawn additional windows
        // hosting the same content.
        WindowGroup("Swift Windows UI", id: "main-dashboard") {
            DemoRootView(model: model)
        }
        // Windows-only: SwiftUI proper has no `windowMinSize` scene modifier
        // (its nearest equivalent is a content floor plus
        // `.windowResizability(.contentMinSize)`), and the demo's shared
        // source must keep building against it unchanged.
        #if !canImport(SwiftUI)
            .windowMinSize(Self.minimumWindowSize)
        #endif
    }
}
