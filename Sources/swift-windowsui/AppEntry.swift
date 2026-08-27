import SwiftWindowsDemo

#if canImport(SwiftUI)
    import SwiftUI
#else
    import class Foundation.ProcessInfo
    import SwiftWindowsGraphics
    import SwiftWindowsRendererD3D11
    import WinSwiftUI
#endif
@main
struct SwiftWindowsUIDemoApp: App {
    private let model: DemoDashboardModel

    init() {
        #if canImport(SwiftUI)
            model = DemoDashboardModel(rendererIdentity: .nativeSwiftUI, settingsStore: .application)
        #else
            let requestedIdentity: DemoRendererIdentity =
                Self.requestsSoftwareBackend ? .software : .direct3D11
            let requestedFactory = Self.renderBackendFactory()
            let resolvedIdentity: DemoRendererIdentity

            if !requestedFactory.probeAvailability().canPresent,
                SoftwareWindowRenderBackendFactory().probeAvailability().canPresent
            {
                // App.main resolves an unavailable graphics factory to this
                // same presenting fallback after initializing the app. Keep
                // its dashboard honest even when that substitution is needed.
                resolvedIdentity = .software
            } else {
                resolvedIdentity = requestedIdentity
            }

            model = DemoDashboardModel(rendererIdentity: resolvedIdentity, settingsStore: .application)
        #endif
    }

    #if !canImport(SwiftUI)
        private static var requestsSoftwareBackend: Bool {
            ProcessInfo.processInfo.environment["SWIFT_WINDOWSUI_RENDER_BACKEND"]?.lowercased() == "software"
        }

        /// Composition root: D3D11 remains the product default, while an
        /// explicit environment selection can prove the same retained app
        /// also presents through the interchangeable software backend.
        /// `WinSwiftUI` itself stays neutral and never imports either engine.
        static func renderBackendFactory() -> RenderBackendFactory {
            if requestsSoftwareBackend {
                return SoftwareWindowRenderBackendFactory()
            }
            return D3D11RenderBackendFactory()
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

        Settings {
            DemoSettingsTemplate(model: model)
        }
    }
}
